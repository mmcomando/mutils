module mutils.container.hash_set;

import core.bitop;
import core.simd: ushort8;
import std.meta;
import std.stdio;
import std.traits;

import mutils.container.vector;


enum ushort emptyMask=1;
enum ushort neverUsedMask=2;
enum ushort hashMask=~emptyMask;
// lower 15 bits - part of hash, last bit - isEmpty
struct Control{	
	ushort b=neverUsedMask;
	
	bool isEmpty(){
		return (b & emptyMask)==0;
	}
	
	/*void setEmpty(){
		b=emptyMask;
	}*/
	
	/*bool cmpHash(size_t hash){
		union Tmp{
			size_t h;
			ushort[size_t.sizeof/2] d;
		}
		Tmp t=Tmp(hash);
		return (t.d[0] & hashMask)==(b & hashMask);
	}*/
	
	void set(size_t hash){
		union Tmp{
			size_t h;
			ushort[size_t.sizeof/2] d;
		}
		Tmp t=Tmp(hash);
		b=(t.d[0] & hashMask) | emptyMask;
	}
}

// Hash helper struct
// hash is made out of two parts[     H1 48 bits      ][ H2 16 bits]
// whole hash is used to find group
// H2 is used to quickly(SIMD) find element in group
struct Hash{
	union{
		size_t h=void;
		ushort[size_t.sizeof/2] d=void;
	}
	this(size_t hash){
		h=hash;
	}
	
	size_t getH1(){
		Hash tmp=h;
		tmp.d[0]=d[0] & emptyMask;//clear H2 hash
		return tmp.h;
	}
	
	ushort getH2(){
		return d[0] & hashMask;
	}
	
	ushort getH2WithLastSet(){
		return d[0] | emptyMask;
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

struct HashSet(T, alias hashFunc=defaultHashFunc){
	static assert(size_t.sizeof==8);// Only 64 bit
	enum rehashFactor=0.85;
	enum size_t getIndexEmptyValue=size_t.max;
	
	
	static struct Group{
		union{
			Control[8] control;
			ushort8 controlVec;
		}
		T[8] elements;
		
		// Prevent error in Vector!Group
		bool opEquals()(auto ref const Group r) const { 
			assert(0);
		}
	}
	
	
	Vector!Group groups;// Length should be always power of 2
	size_t addedElements;// Used to compute loadFactor
	
	float getLoadFactor(size_t forElementsNum){
		if(groups.length==0){
			return 1;
		}
		return cast(float)forElementsNum/(groups.length*8);
	}
	
	void rehash(){
		mixin(doNotInline);
		// Get all elements
		Vector!T allElements;
		allElements.reserve(groups.length);
		
		foreach(ref Control c,ref T el; this){
			allElements~=el;
			c=Control.init;
		}

		if(getLoadFactor(addedElements+1)>rehashFactor){// Reallocate
			groups.length=(groups.length?groups.length:1)<<1;// Power of two
		}

		// Insert elements
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
		size_t group=index/8;
		size_t elIndex=index%8;
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
		int group=hashMod(hash.h);// Starting point
		uint groupSkip=0;
		while(true){
			Group* gr=&groups[group];
			foreach(i, ref Control c; gr.control){
				if(c.isEmpty){
					c.set(hash.h);
					gr.elements[i]=el;
					return;
				}
			}
			group++;
			if(group>=groups.length){
				group=0;
			}
		}
	}
	
	// Returns ushort with bits set to 1 if control matches check
	static auto getMatchSIMD(ushort8 control, ushort check){
		ushort8 v=ushort8(check);
		version(DigitalMars){
			import core.simd: __simd, ubyte16, XMM;
			ubyte16 ok=__simd(XMM.PCMPEQW, control, v);
			ubyte16 bitsMask=[1,2,4,8,16,32,64,128,1,2,4,8,16,32,64,128];
			ubyte16 bits=bitsMask&ok;
			ubyte16 zeros=0;
			ushort8 vv=__simd(XMM.PSADBW, bits, zeros);
			ushort num=cast(ushort)(vv[0]+vv[4]*256);
		}else version(LDC){
			import ldc.simd;
			import ldc.gccbuiltins_x86;
			ushort8 ok = equalMask!ushort8(control, v);
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

	// For debug
	/*int numA;
	int numB;
	int numC;*/


	size_t getIndex(T el){
		mixin(doNotInline);
		size_t groupsLength=groups.length;
		if(groupsLength==0){
			return getIndexEmptyValue;
		}
		
		Hash hash=Hash(hashFunc(el));
		size_t mask=groupsLength-1;
		size_t group=cast(int)(hash.h & mask);// Starting point	
		//numA++;
		while(true){
			//numB++;
			Group* gr=&groups[group];
			int cntrlV=getMatchSIMD(gr.controlVec, hash.getH2WithLastSet);// Compare 8 controls at once to h2
			while( true){
				//numC++;
				int ffInd=ffsl(cntrlV);
				if(ffInd==0){// Element is not present in this group
					break;
				}
				int i=(ffInd-1)/2;// Find first set bit and divide by 2 to get element index
				if(gr.elements.ptr[i]==el){
					return group*8+i;
				}
				cntrlV&=0xFFFF_FFFF<<(ffInd+1);
			}
			cntrlV=getMatchSIMD(gr.controlVec, neverUsedMask);// If there is neverUsed element, we will never find our element
			if(cntrlV!=0){
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
unittest{
	HashSet!(int) set;
	
	ushort8 control=15;
	control.array[0]=10;
	control.array[7]=10;
	ushort check=15;
	ushort ret=set.getMatchSIMD(control, check);
	assert(ret==0b0011_1111_1111_1100);
	
}
import mutils.benchmark;
unittest{
	HashSet!(int) set;
	
	assert(set.isIn(123)==false);
	set.add(123);
	set.add(123);
	assert(set.isIn(123)==true);
	assert(set.isIn(122)==false);
	assert(set.addedElements==1);
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
	uint elementsNumToAdd=200;//cast(uint)(64536*0.9);
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
	foreach(int i;elementsNumToAdd..elementsNumToAdd+10_000){
		assert(!set.isIn(i));
		assert((i in mapStandard) is null);
	}
	//writeln(set.getLoadFactor(set.addedElements));
	//set.numA=set.numB=set.numC=0;
	enum itNum=100;
	BenchmarkData!(2, itNum) bench;
	doNotOptimize(set);// Make some confusion for compiler
	doNotOptimize(mapStandard);
	ushort myResults;
	myResults=0;
	//benchmark standard library implementation
	foreach(b;0..itNum){
		bench.start!(1)(b);
		foreach(i;0..1000_000){
			auto ret=myResults in mapStandard;
			myResults+=1;//cast(typeof(myResults))(cast(bool)ret);
			doNotOptimize(ret);
		}
		bench.end!(1)(b);
	}
	
	auto stResult=myResults;
	//benchmark this implementation
	myResults=0;
	foreach(b;0..itNum){
		bench.start!(0)(b);
		foreach(i;0..1000_000){
			auto ret=set.isIn(myResults);
			myResults+=1;//cast(typeof(myResults))(ret);
			doNotOptimize(ret);
		}
		bench.end!(0)(b);
	}
	assert(myResults==stResult);//same behavior as standard map
	//writeln(set.numA);
	//writeln(set.numB);
	//writeln(set.numC);
	
	doNotOptimize(myResults);
	bench.plotUsingGnuplot("test.png",["my", "standard"]);
	set.saveGroupDistributionPlot("distr.png");	
}


void benchmarkHashSetPerformancePerElement(){
	ushort trueResults;
	doNotOptimize(trueResults);
	enum itNum=1000;
	BenchmarkData!(2, itNum) bench;
	HashSet!(int) set;
	byte[int] mapStandard;
	//writeln(set.getLoadFactor(set.addedElements));
	//set.numA=set.numB=set.numC=0;
	size_t lastAdded;
	size_t numToAdd=16*8;

	foreach(b;0..itNum){
		foreach(i;lastAdded..lastAdded+numToAdd){
			mapStandard[cast(uint)i]=true;
		}
		lastAdded+=numToAdd;
		bench.start!(1)(b);
		foreach(i;0..1000_00){
			auto ret=trueResults in mapStandard;
			trueResults+=1;//cast(typeof(trueResults))(cast(bool)ret);
			doNotOptimize(ret);
		}
		bench.end!(1)(b);
	}
	lastAdded=0;
	trueResults=0;
	foreach(b;0..itNum){
		foreach(i;lastAdded..lastAdded+numToAdd){
			set.add(cast(uint)i);
		}
		lastAdded+=numToAdd;
		bench.start!(0)(b);
		foreach(i;0..1000_00){
			auto ret=set.isIn(trueResults);
			trueResults+=1;//cast(typeof(trueResults))(ret);
			doNotOptimize(ret);
		}
		bench.end!(0)(b);
	}

	/*writeln(set.numA);
	writeln(set.numB);
	writeln(set.numC);*/
	doNotOptimize(trueResults);
	bench.plotUsingGnuplot("test.png",["my", "standard"]);
	//set.saveGroupDistributionPlot("distr.png");

}


