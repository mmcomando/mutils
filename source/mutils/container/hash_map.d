module mutils.container.hash_map;

import core.bitop;
import core.simd: ubyte16;
import std.meta;
import std.stdio;

import mutils.container.vector;


enum emptyMask=0b0000_0001;
enum hashMask=0b1111_1110;
// lower 7 bits - part of hash, last bit - isEmpty
static struct Control{
	
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
		return (t.d[0] & hashMask)==(b & hashMask);
	}
	
	void set(size_t hash){
		union Tmp{
			size_t h;
			ubyte[size_t.sizeof] d;
		}
		Tmp t=Tmp(hash);
		b=(t.d[0] & hashMask) | emptyMask;
	}
}

// hash
static struct Hash{
	nothrow @nogc @system:
	union{
		size_t h=void;
		ubyte[size_t.sizeof] d=void;
	}
	this(size_t hash){
		h=hash;
	}
	
	size_t getH1(){
		Hash tmp=h;
		tmp.d[0]=d[0] & emptyMask;//clear H2 hash
		return tmp.h;
	}
	
	ubyte getH2(){
		return d[0] & hashMask;
	}
	
	ubyte getH2WithLastSet(){
		return d[0] | emptyMask;
	}
	
}
size_t defaultHashFunc(T)(ref T t){
	return t.hashOf;
}

ulong hashIntNone(ulong x) nothrow @nogc @system{
	pragma(inline, true);
	return x;
}

ulong hashInt1(ulong x) nothrow @nogc @system{
	pragma(inline, true);
	return (x | 64) ^ ((x >>> 15) | (x << 17));
}

ulong hashInt2(ulong x) nothrow @nogc @system{
	pragma(inline, true);
	x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9;
	x = (x ^ (x >> 27)) * 0x94d049bb133111eb;
	x = x ^ (x >> 31);
	return x;
}

extern(C) int ffsll(long i) nothrow @nogc @system;
struct HashSet(T, alias hashFunc=defaultHashFunc){
	static assert(size_t.sizeof==8);// Only 64 bit
	enum rehashFactor=0.95;

	// Table for fast power of 2 modulo
	immutable static uint[] moduloMaskTable=[0b0,0b1,0b11,0b111,0b1111,0b1111_1,0b1111_11,0b1111_111,0b1111_1111,0b1111_1111_1,0b1111_1111_11,0b1111_1111_111,0b1111_1111_111];
	alias powerOf2s=AliasSeq!(1,2,4,8,16,32,64,128,256,512,1024,2048,4096);
	static assert(moduloMaskTable.length==powerOf2s.length);

	
	union ControlView{
		ubyte16 vec;
		ulong[2] l;
	}

	static struct Group{
		union{
			ubyte16 controlVec;
			Control[16] control;
		}
		T[16] elements;
	}

	
	Vector!Group groups;// Length should be always power of 2
	size_t addedElements;//Used to compute loadFactor
	uint exponent;
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
				assert(0);
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

	


	void add(T el){
		if(getLoadFactor(addedElements+1)>rehashFactor){
			rehash();
		}
		addedElements++;
		Hash hash=Hash(hashFunc(el));
		int group=cast(uint)(hash.h%cast(short)groups.length);
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
		pragma(inline, true);
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
		
		return ret;
	}

	uint hashMod(size_t hash){
		pragma(inline, true);
		return cast(uint)(hash & moduloMaskTable.ptr[exponent]);
	}


	bool isIn(T el){
		mixin(doNotInline);
		size_t groupsLength=groups.length;
		if(groupsLength==0){
			return false;
		}
		Hash hash=Hash(hashFunc(el));
		ubyte h2=hash.getH2WithLastSet;// Searched byte in control
		int group=hashMod(hash.h);// Starting point
		ControlView cntrlV; // Treat contrls array as ubyte16 ot two longs
		uint groupScanned=0;// How many groups we scanned
		while(true){
			Group* gr=&groups[group];
			cntrlV.vec=getMatchSIMD(gr.controlVec, h2);// Compare 16 contols at once to h2
			while( (cntrlV.l[0]!=0) | (cntrlV.l[1]!=0)){
				bool ind=cntrlV.l[0]==0;// Watch  first or second long
				int i=(ffsll(cntrlV.l[ind])-1)>>3;// Find first set bit and divide by 8 to get element index
				if(gr.elements[8*ind+i]==el){
					return true;
				}
				cntrlV.vec.ptr[8*ind+i]=0x00;// Clear byte so ffsll won't catch it again
			}
			if(groupScanned>=maxGroupsSkip){// Element don't exist, during add there was never such a big skip 
				return false;
			}
			groupScanned++;
			group++;
			if(group>=groupsLength){
				group=0;
			}
		}

	}

}

import mutils.benchmark;
unittest{
	HashSet!(int) map;
	assert(map.isIn(123)==false);
	map.add(123);
	assert(map.addedElements==1);
	assert(map.isIn(122)==false);
	assert(map.isIn(123)==true);
	//assert(addedElements==0);

	
	foreach(i;1..130){
		map.add(i);		
	}

	foreach(i;1..130){
		assert(map.isIn(i));
	}

	foreach(i;130..500){
		assert(!map.isIn(i));
	}
}

void test(){
	HashSet!(int, hashIntNone) map;
	//HashSet!(int) map;
	byte[int] mapStandard;
	foreach(int i;0..20000){
		map.add(i);
		mapStandard[i]=true;
	}

	foreach(int i;0..2000){
		assert(map.isIn(i));
		assert((i in mapStandard) !is null);
	}
	foreach(int i;20000..1000_000_00){
		assert(!map.isIn(i));
		assert((i in mapStandard) is null);
	}

	enum itNum=1;
	BenchmarkData!(2, itNum) bench;
	
	doNotOptimize(map);
	doNotOptimize(mapStandard);
	ushort aaa;
	foreach(b;0..itNum){
		bench.start!(0)(b);
		foreach(i;0..1000_000_00){
			auto ret=map.isIn(aaa);
			aaa+=cast(ushort)(ret*7+1);
			doNotOptimize(ret);
		}
		bench.end!(0)(b);
	}
	writeln(aaa);
	aaa=0;
	foreach(b;0..itNum){
		bench.start!(1)(b);
		foreach(i;0..1000_000_00){
			auto ret=aaa in mapStandard;
			aaa+=cast(ushort)(cast(bool)ret*7+1);
			doNotOptimize(ret);
		}
		bench.end!(1)(b);
	}
	writeln(aaa);

	doNotOptimize(aaa);
	//bench.writeToCsvFile("test.csv",["my", "standard"]);
	bench.plotUsingGnuplot("test.png",["my", "standard"]);
}