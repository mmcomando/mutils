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

ulong hashInt(ulong x){
	x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9;
	x = (x ^ (x >> 27)) * 0x94d049bb133111eb;
	x = x ^ (x >> 31);
	return x;
}


extern(C) int ffsll(long i) nothrow @nogc @system;

//It is very importnant to have hashing function with distribution over all bits (hash is divided to two parts H1 57bit and H2 7bit)
struct HashSet(T, alias hashFunc=defaultHashFunc){
	static assert(size_t.sizeof==8);// Only 64 bit
	enum rehashFactor=0.95;

	// Table for fast power of 2 modulo
	immutable static uint[] moduloMaskTable=[0b0,0b1,0b11,0b111,0b111_1,0b111_11,0b111_111,0b111_111_1,0b111_111_11,0b111_111_111,0b111_111_111_1,0b111_111_111_11,0b111_111_111_111,0b111_111_111_111_1,0b111_111_111_111_11,0b111_111_111_111_111];
	alias powerOf2s=AliasSeq!(1,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384,32768);
	static assert(moduloMaskTable.length==powerOf2s.length);

	
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
	uint exponent;// Needed for division lookuptable
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
	sw:switch(groups.length){
			foreach(i, d;powerOf2s){
				case d:
				exponent=i;
				break sw;					
			}
			default:
				assert(0, "Too many elements in map");
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
		uint index=getIndex(el);
		if(index==uint.max){
			return false;
		}
		addedElements--;
		int group=index/16;
		int elIndex=index%16;
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

	// Where byte is equal to check byte is set to 0xFF
	static auto getMatchSIMD(ubyte16 control, ubyte check){
		ubyte16 v=check;
		version(DigitalMars){
			import core.simd: __simd, XMM;
			ubyte16 ret=__simd(XMM.PCMPEQB, control, v);
		}else version(LDC){
			import ldc.simd;
			ubyte16 ret = equalMask!ubyte16(control, v);
		}else{
			static assert(0);
		}
		
		return ret;// Could squish to ushort but might not be portable
	}
	// Division is expensive use lookuptable
	uint hashMod(size_t hash) nothrow @nogc @system{
		pragma(inline, true);
		return cast(uint)(hash & moduloMaskTable.ptr[exponent]);
	}

	bool isIn(T el){
		return getIndex(el)!=uint.max;
	}

	uint getIndex(T el){
		size_t groupsLength=groups.length;
		if(groupsLength==0){
			return uint.max;
		}
		Hash hash=Hash(hashFunc(el));
		ubyte h2=hash.getH2WithLastSet;// Searched byte in control
		int group=hashMod(hash.getH1);// Starting point
		ControlView cntrlV; // Treat contrls array as ubyte16 or two longs
		//uint groupScanned=0;// How many groups we scanned
		uint groupExit=group+maxGroupsSkip;
		groupExit=hashMod(groupExit);// Element don't exist, during add there was never such a big skip 
		if(groupExit>=groupsLength){
			groupExit-=groupsLength;
		}
		while(true){
			Group* gr=&groups[group];
			cntrlV.vec=getMatchSIMD(gr.controlVec, h2);// Compare 16 contols at once to h2
			while( (cntrlV.l[0]!=0) | (cntrlV.l[1]!=0)){
				bool ind=cntrlV.l[0]==0;// Watch  first or second long
				int i=(ffsll(cntrlV.l[ind])-1)>>3;// Find first set bit and divide by 8 to get element index
				int elIndex=8*ind+i;
				if(gr.elements.ptr[elIndex]==el){
					return group*16+elIndex;
				}
				cntrlV.vec.ptr[elIndex]=0x00;// Clear byte so ffsll won't catch it again
			}
			if(group==groupExit){
				return uint.max;
			}
			group++;
			if(group>=groupsLength){
				group=0;
			}
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
		//assert(groups.length<=8192);
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
	uint elementsNumToAdd=300;
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

	enum itNum=100;
	BenchmarkData!(2, itNum) bench;
	doNotOptimize(set);// Make some confusion for compiler
	doNotOptimize(mapStandard);
	ubyte trueResults;
	//benchmark this implementation
	trueResults=0;
	foreach(b;0..itNum){
		bench.start!(1)(b);
		foreach(i;0..1000_00){
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
		foreach(i;0..1000_00){
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

