module mutils.container.hash_set;

import core.bitop;
import core.simd: ushort8;
import std.meta;
import std.stdio;
import std.traits;

import mutils.benchmark;
import mutils.container.vector;
import mutils.traits;

version(DigitalMars){
	import core.bitop;
	alias firstSetBit=bsr;// DMD treats it as intrinsics
}else version(LDC){
	import ldc.intrinsics;
	int firstSetBit(int i){
		return llvm_cttz(i, true)+1;
	}
}else{
	static assert("Compiler not supported.");
}

enum ushort emptyMask=1;
enum ushort neverUsedMask=2;
enum ushort hashMask=~emptyMask;
// lower 15 bits - part of hash, last bit - isEmpty
struct Control{	
	nothrow @nogc @safe:

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
	nothrow @nogc @safe:
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

size_t defaultHashFunc(T)(auto ref T t){
	static if (isIntegral!(T)){
		return hashInt(t);
	}else{
		return hashInt(t.hashOf);// hashOf is not giving proper distribution between H1 and H2 hash parts
	}
}

// Can turn bad hash function to good one
ulong hashInt(ulong x) nothrow @nogc @safe {
	x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9;
	x = (x ^ (x >> 27)) * 0x94d049bb133111eb;
	x = x ^ (x >> 31);
	return x;
}

// ADV additional value - used to implement HashMap without unnecessary copies
struct HashSet(T, alias hashFunc=defaultHashFunc, ADV...){
	static assert(ADV.length<=1);// ADV is treated as a optional additional value type
	static assert(size_t.sizeof==8);// Only 64 bit
	enum hasValue=ADV.length==1;
	enum rehashFactor=0.85;
	enum size_t getIndexEmptyValue=size_t.max;

	static struct Group{
		union{
			Control[8] control;
			ushort8 controlVec;
		}
		T[8] elements;
		static if(hasValue)ADV[0][8] values;
		
		// Prevent error in Vector!Group
		bool opEquals()(auto ref const Group r) const { 
			assert(0);
		}
	}

	void clear(){
		groups.clear();
		addedElements=0;
	}

	void reset(){
		groups.reset();
		addedElements=0;
	}

	
	Vector!Group groups;// Length should be always power of 2
	size_t addedElements;// Used to compute loadFactor
	
	float getLoadFactor(size_t forElementsNum) {
		if(groups.length==0){
			return 1;
		}
		return cast(float)forElementsNum/(groups.length*8);
	}
	import mutils.utils;
	void rehash() {
		mixin(doNotInline);
		// Get all elements
		Vector!T allElements;
		allElements.reserve(groups.length);
		static if(hasValue)Vector!(ADV[0]) allValues;
		static if(hasValue)allValues.reserve(groups.length);
		static if(hasValue){
			foreach(ref Control c, ref T el, ref ADV[0] val; this){
				allElements~=el;
				allValues~=val;
				c=Control.init;
			}
		}else{
			foreach(ref Control c, ref T el; this){
				allElements~=el;
				c=Control.init;
			}
		}

		if(getLoadFactor(addedElements+1)>rehashFactor){// Reallocate
			groups.length=(groups.length?groups.length:1)<<1;// Power of two
		}
	
		// Insert elements
		foreach(i,ref el;allElements){
			static if(hasValue){
				add(el, allValues[i]);
			}else{
				add(el);
			}
		}
		addedElements=allElements.length;
		//allElements.clear();
	}
	
	size_t length(){
		return addedElements;
	}
	
	bool tryRemove(T el) {
		size_t index=getIndex(el);
		if(index==getIndexEmptyValue){
			return false;
		}
		addedElements--;
		size_t group=index/8;
		size_t elIndex=index%8;
		groups[group].control[elIndex]=Control.init;
		//TODO value destructor
		return true;
	}

	void remove(T el) {
		bool ok=tryRemove(el);
		assert(ok);
	}

	void add(T el, ADV value){
		add(el, value);
	}
	void add(ref T el, ADV value){
		if(isIn(el)){
			return;
		}
		
		if(getLoadFactor(addedElements+1)>rehashFactor){
			assumeNoGC(&rehash)();// rehash is @nogc but compiler cannot deduce that because rehash calls add internally
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
					static if(hasValue)gr.values[i]=value[0];
					return;
				}
			}
			group++;
			if(group>=groups.length){
				group=0;
			}
		}
	}
	
	// Sets bits in ushort where value in control matches check value
	// Ex. control=[0,1,2,3,4,5,6,7], check=2, return=0b0000_0000_0011_0000
	static auto matchSIMD(ushort8 control, ushort check) @nogc {
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

	bool isIn(ref T el){
		return getIndex(el)!=getIndexEmptyValue;
	}

	bool isIn(T el){
		return getIndex(el)!=getIndexEmptyValue;
	}

	// For debug
	/*int numA;
	 int numB;
	 int numC;*/


	size_t getIndex(T el) {
		return getIndex(el);
	}

	size_t getIndex(ref T el) {
		//mixin(doNotInline);
		size_t groupsLength=groups.length;
		if(groupsLength==0){
			return getIndexEmptyValue;
		}
		
		Hash hash=Hash(hashFunc(el));
		size_t mask=groupsLength-1;
		size_t group=cast(int)(hash.h & mask);// Starting point	
		//numA++;
		while( true ){
			//numB++;
			Group* gr=&groups[group];
			int cntrlV=matchSIMD(gr.controlVec, hash.getH2WithLastSet);// Compare 8 controls at once to h2
			while( cntrlV!=0 ){
				//numC++;
				int ffInd=firstSetBit(cntrlV);
				int i=ffInd/2;// Find first set bit and divide by 2 to get element index
				if( gr.elements.ptr[i]==el ){
					return group*8+i;
				}
				cntrlV&=0xFFFF_FFFF<<(ffInd+1);
			}
			cntrlV=matchSIMD(gr.controlVec, neverUsedMask);// If there is neverUsed element, we will never find our element
			if( cntrlV!=0 ){
				return getIndexEmptyValue;
			}
			group++;
			group=group & mask;
		}
		
	}	
	// foreach support
	int opApply(DG)(scope DG  dg) { 
		int result;
		foreach(ref Group gr; groups){
			foreach(i, ref Control c; gr.control){
				if(c.isEmpty){
					continue;
				}
				static if(hasValue && isForeachDelegateWithTypes!(DG, Control, T, ADV[0]) ){
					result=dg(gr.control[i], gr.elements[i], gr.values[i]);
				}else static if( isForeachDelegateWithTypes!(DG, Control, T) ){
					result=dg(gr.control[i], gr.elements[i]);
				}else static if( isForeachDelegateWithTypes!(DG, T) ){
					result=dg(gr.elements[i]);
				}else{
					static assert(0);
				}
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



@nogc nothrow pure unittest{	
	ushort8 control=15;
	control.array[0]=10;
	control.array[7]=10;
	ushort check=15;
	ushort ret=HashSet!(int).matchSIMD(control, check);
	assert(ret==0b0011_1111_1111_1100);	
}

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
			myResults+=1+cast(bool)ret;//cast(typeof(myResults))(cast(bool)ret);
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
			myResults+=1+ret;//cast(typeof(myResults))(ret);
			doNotOptimize(ret);
		}
		bench.end!(0)(b);
	}
	assert(myResults==stResult);// Same behavior as standard map
	 //writeln(set.getLoadFactor(set.addedElements));
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
	//writeln(set.numA);
	//writeln(set.numB);
	// writeln(set.numC);
	doNotOptimize(trueResults);
	bench.plotUsingGnuplot("test.png",["my", "standard"]);
	//set.saveGroupDistributionPlot("distr.png");

}
