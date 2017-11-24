module mutils.container.hash_set;

import core.bitop;
import core.simd: ubyte16;
import std.meta;
import std.stdio;
import std.traits;

import mutils.container.vector;


enum emptyMask=0b0000_0001;
enum hashMask=0b1111_1110;
// lower 7 bits - part of hash, last bit - isEmpty
struct Control{	
	ubyte b=0;
	
	bool isEmpty(){
		return (b & emptyMask)==0;
	}
	
	void setEmpty(){
		b=emptyMask;
	}
	
	bool cmpHash(size_t hash){
		union Tmp{
			size_t h;
			ubyte[size_t.sizeof] d;
		}
		Tmp t=Tmp(hash);
		return (t.d[7] & hashMask)==(b & hashMask);
	}
	
	void set(size_t hash){
		union Tmp{
			size_t h;
			ubyte[size_t.sizeof] d;
		}
		Tmp t=Tmp(hash);
		b=(t.d[7] & hashMask) | emptyMask;
	}
}

// Hash helper struct
// hash is made out of two parts[     H1 57 bits      ][ H2 7bits]
// H1 is used to find group
// H2 is used quick(SIMD) find element in group
struct Hash{
	union{
		size_t h=void;
		ubyte[size_t.sizeof] d=void;
	}
	this(size_t hash){
		h=hash;
	}
	
	size_t getH1(){
		Hash tmp=h;
		tmp.d.ptr[7]=d.ptr[7] & emptyMask;//clear H2 hash
		return tmp.h;
	}
	
	ubyte getH2(){
		return d.ptr[7] & hashMask;
	}
	
	ubyte getH2WithLastSet(){
		return d.ptr[7] | emptyMask;
	}
	
}

size_t defaultHashFunc(T)(ref T t){
	static if (isIntegral!(T)){
		return hashInt(t);
	}else{
		return hashInt(t.hashOf);// hashOf is not giving proper distribution between H1 and H2 hash parts
	}
}

// Can turn bad hash function to good one
ulong hashInt(ulong x){
	x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9;
	x = (x ^ (x >> 27)) * 0x94d049bb133111eb;
	x = x ^ (x >> 31);
	return x;
}


extern(C) int ffsl(int i) nothrow @nogc @system;
extern(C) int ffsll(long i) nothrow @nogc @system;

//It is very importnant to have hashing function with distribution over all bits (hash is divided to two parts H1 57bit and H2 7bit)
struct HashSet(T, alias hashFunc=defaultHashFunc){
	static assert(size_t.sizeof==8);// Only 64 bit
	enum rehashFactor=0.95;

	union ControlView{
		ubyte16 vec;
		ulong[2] l;
	}

	static struct Group{
		union{
			Control[16] control;
			ubyte16 controlVec;
		}
		T[16] elements;

		// Prevent error in Vector!Group
		bool opEquals()(auto ref const Group r) const { 
			assert(0);
		}
	}

	
	Vector!Group groups;// Length should be always power of 2
	size_t addedElements;//Used to compute loadFactor
	uint maxGroupsSkip;// How many groups where skped during add, max

	float getLoadFactor(size_t forElementsNum){
		if(groups.length==0){
			return 1;
		}
		return cast(float)forElementsNum/(groups.length*16);
	}

	void rehash(){
		mixin(doNotInline);
		size_t startLength=groups.length;
		if(getLoadFactor(addedElements+1)>rehashFactor){
			groups~=Group();
			// Length to power of 2
			foreach(i;0..groups.capacity){
				groups~=Group();
			}
		}

		Vector!T allElements;
		allElements.reserve(addedElements);
		foreach(ref Group gr; groups[0..startLength]){
			foreach(i, ref Control c; gr.control){
				if(!c.isEmpty){
					allElements~=gr.elements[i];
				}
				c=Control.init;
			}
		}

		maxGroupsSkip=0;
		foreach(el;allElements){
			add(el);
		}
		addedElements=allElements.length;
		allElements.clear();
	}

	bool tryRemove(T el){
		size_t index=getIndex(el);
		if(index==getIndexEmptyValue){
			return false;
		}
		addedElements--;
		size_t group=index/16;
		size_t elIndex=index%16;
		groups[group].control[elIndex]=Control.init;
		return true;
	}

	void remove(T el){
		assert(tryRemove(el));
	}

	void add(T el){
		if(isIn(el)){
			return;
		}

		if(getLoadFactor(addedElements+1)>rehashFactor){
			rehash();
		}
		addedElements++;
		Hash hash=Hash(hashFunc(el));
		int group=hashMod(hash.getH1);// Starting point
		uint groupSkip=0;
		while(true){
			Group* gr=&groups[group];
			foreach(i, ref Control c; gr.control){
				if(c.isEmpty){
					c.set(hash.h);
					gr.elements[i]=el;
					if(groupSkip>maxGroupsSkip){
						maxGroupsSkip=groupSkip;
					}
					return;
				}
			}
			groupSkip++;
			group++;
			if(group>=groups.length){
				group=0;
			}
		}
	}

	// Returns ushort with bits set to 1 if control matches check
	static auto getMatchSIMD(ubyte16 control, ubyte check){
		ubyte16 v=check;
		version(DigitalMars){
			import core.simd: __simd, ushort8, XMM;
			ubyte16 ok=__simd(XMM.PCMPEQB, control, v);
			ubyte16 bitsMask=[1,2,4,8,16,32,64,128, 1,2,4,8,16,32,64,128];
			ubyte16 bits=bitsMask&ok;
			ubyte16 zeros=0;
			ushort8 vv=__simd(XMM.PSADBW, bits, zeros);
			ushort num=cast(ushort)(vv[0]+vv[4]*256);
		}else version(LDC){
			import ldc.simd;
			import ldc.gccbuiltins_x86;
			ubyte16 ok = equalMask!ubyte16(control, v);
			ushort num=cast(ushort)__builtin_ia32_pmovmskb128(ok);
		}else{
			static assert(0);
		}
		
		return num;
	}
	// Division is expensive use lookuptable
	int hashMod(size_t hash) nothrow @nogc @system{
		return cast(int)(hash & (groups.length-1));
	}

	bool isIn(T el){
		return getIndex(el)!=getIndexEmptyValue;
	}

	enum size_t getIndexEmptyValue=size_t.max;

	size_t getIndex(T el){
		mixin(doNotInline);
		size_t groupsLength=groups.length;
		if(groupsLength==0){
			return getIndexEmptyValue;
		}

		Hash hash=Hash(hashFunc(el));
		size_t mask=groupsLength-1;
		size_t group=cast(int)(hash.getH1 & mask);// Starting point	
		size_t groupExit=(group+maxGroupsSkip)& mask;
		
		while(true){
			Group* gr=&groups[group];
			int cntrlV=getMatchSIMD(gr.controlVec, hash.getH2WithLastSet);// Compare 16 contols at once to h2
			while( true){
				int ffInd=ffsl(cntrlV);
				if(ffInd==0){// All bits are 0
					break;
				}
				int i=ffInd-1;// Find first set bit and divide by 8 to get element index
				if(gr.elements.ptr[i]==el){
					return group*16+i;
				}
				cntrlV&=0xFFFF<<ffInd;
			}
			if(group==groupExit){
				return getIndexEmptyValue;
			}
			group++;
			group=group & mask;
		}

	}

	// foreach support
	int opApply(scope int delegate(ref T) dg){ 
		int result;
		foreach(ref Group gr; groups){
			foreach(i, ref Control c; gr.control){
				if(c.isEmpty){
					continue;
				}

				result=dg(gr.elements[i]);
				if (result)
					break;	
				}
		}		

		return result;
	}

	// foreach support
	int opApply(scope int delegate(ref Control c,ref T) dg){ 
		int result;
		foreach(ref Group gr; groups){
			foreach(i, ref Control c; gr.control){
				if(c.isEmpty){
					continue;
				}
				
				result=dg(gr.control[i], gr.elements[i]);
				if (result)
					break;	
			}
		}		
		
		return result;
	}

	void saveGroupDistributionPlot(string path){
		BenchmarkData!(1, 8192) distr;// For now use benchamrk as a plotter

		foreach(ref T el; this){
			int group=hashMod(hashFunc(el));
			if(group>=8192){
				continue;
			}
			distr.times[0][group]++;

		}
		distr.plotUsingGnuplot(path, ["group distribution"]);
	}

}

import mutils.benchmark;
unittest{
	HashSet!(int) set;

	assert(set.isIn(123)==false);
	set.add(123);
	set.add(123);
	assert(set.addedElements==1);
	assert(set.isIn(122)==false);
	assert(set.isIn(123)==true);
	set.remove(123);
	assert(set.isIn(123)==false);
	assert(set.addedElements==0);
	assert(set.tryRemove(500)==false);
	set.add(123);
	assert(set.tryRemove(123)==true);

	
	foreach(i;1..130){
		set.add(i);		
	}

	foreach(i;1..130){
		assert(set.isIn(i));
	}

	foreach(i;130..500){
		assert(!set.isIn(i));
	}

	foreach(int el; set){
		assert(set.isIn(el));
	}
}

void benchmarkHashSetInt(){
	HashSet!(int) set;
	byte[int] mapStandard;
	uint elementsNumToAdd=3500;
	// Add elements
	foreach(int i;0..elementsNumToAdd){
		set.add(i);
		mapStandard[i]=true;
	}
	// Check if isIn is working
	foreach(int i;0..elementsNumToAdd){
		assert(set.isIn(i));
		assert((i in mapStandard) !is null);
	}
	// Check if isIn is returning false properly
	foreach(int i;elementsNumToAdd..1000_0000){
		assert(!set.isIn(i));
		assert((i in mapStandard) is null);
	}
	writeln(set.getLoadFactor(set.addedElements));

	enum itNum=100;
	BenchmarkData!(2, itNum) bench;
	doNotOptimize(set);// Make some confusion for compiler
	doNotOptimize(mapStandard);
	ushort trueResults;
	//benchmark this implementation
	trueResults=0;
	foreach(b;0..itNum){
		bench.start!(1)(b);
		foreach(i;0..1000_000){
			auto ret=trueResults in mapStandard;
			trueResults+=cast(typeof(trueResults))(cast(bool)ret);
			doNotOptimize(ret);
		}
		bench.end!(1)(b);
	}

	auto myResult=trueResults;
	//benchmark standard library implementation
	trueResults=0;
	foreach(b;0..itNum){
		bench.start!(0)(b);
		foreach(i;0..1000_000){
			auto ret=set.isIn(trueResults);
			trueResults+=cast(typeof(trueResults))(ret);
			doNotOptimize(ret);
		}
		bench.end!(0)(b);
	}
	assert(trueResults==myResult);//same behavior as standard map

	doNotOptimize(trueResults);
	bench.plotUsingGnuplot("test.png",["my", "standard"]);
	set.saveGroupDistributionPlot("distr.png");

}

