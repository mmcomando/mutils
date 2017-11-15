module mutils.container.hash_map;

import std.stdio;
import core.simd: VectorSIMD=Vector, ubyte16;

import mutils.container.vector;


enum emptyMask=0b0000_0001;
enum hashMask=0b1111_1110;
// lower 7 bits - part of hash, last bit - isEmpty
static struct Control{
	
	ubyte b=0b0000_0000;
	
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

ulong hashFunc(ulong key) nothrow @nogc @system{
	pragma(inline, true);
	return key;
	//return (key | 64) ^ ((key >>> 15) | (key << 17));
	/*x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9;
	x = (x ^ (x >> 27)) * 0x94d049bb133111eb;
	x = x ^ (x >> 31);
	return x;*/
}
extern(C) int ffsll(long i) nothrow @nogc @system;
struct HashSet(T){
	static assert(size_t.sizeof==8);// For now only 64 bit
	enum elNumInGroup=16;
	enum rehashFactor=0.75;

	

	static struct Group{
		//Control[elNumInGroup] control;
		ubyte16 control;
		T[elNumInGroup] elements;
	}

	
	Vector!Group groups;
	size_t addedElements;
	uint potega;

	float getLoadFactor(size_t forElementsNum){
		if(groups.length==0){
			return 1;
		}
		return cast(float)forElementsNum/(groups.length*elNumInGroup);
	}

	void rehash(){
		mixin(doNotInline);
		size_t startLength=groups.length;
		if(getLoadFactor(addedElements+1)>rehashFactor){
			groups~=Group();
			foreach(i;0..groups.capacity){
				groups~=Group();
			}
		}

		alias nums=AliasSeq!(1,2,4,8,16,32,64,128,256,512,1024,2048,4096);
		immutable static int[] sh=[0,1,2,3,4,5,6,7,8,9,10,11,12];
	sw:switch(groups.length){
				foreach(i, d;nums){
					case d:
					potega=sh[i];
					break sw;
					
				}
			default:
				assert(0);
		}
		Vector!T allElements;
		allElements.reserve(addedElements);
		foreach(ref Group gr; groups[0..startLength]){
			foreach(i, ref ubyte b; gr.control.array){
				Control c=Control(b);
				if(!c.isEmpty){
					allElements~=gr.elements[i];
				}
				b=0;
				//c=Control.init;
			}
		}

		foreach(el;allElements){
			add(el);
		}
		addedElements=allElements.length;
		allElements.clear();
	}


	import std.meta;
	auto getMatchSIMD22(ubyte16 control, ubyte check){
		pragma(inline, true);
		ubyte16 v=check;
		version(DigitalMars){
			import core.simd;
			ubyte16 ret=__simd(XMM.PCMPEQB, control, v);
		}else version(LDC){
			import ldc.simd;
			ubyte16 ret = equalMask!ubyte16(control, v);
		}else{
			static assert(0);
		}

		return ret;
	}
	//import core.simd;
	import std.meta;
	auto getMatchSIMD33(ubyte16 control, ubyte check){
		ubyte16 v=check;
		version(DigitalMars){
			import core.simd;
			ubyte16 ret=__simd(XMM.PCMPEQB, control, v);
		}else version(LDC){
			import ldc.simd;
			ubyte16 ret = equalMask!ubyte16(control, v);
		}else{
			static assert(0);
		}

		//return ret;
		//writeln(ret.array);
		alias nums=AliasSeq!(0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15);
		union Ret{
			ushort num=0x00;
			ubyte[2] n;
		}
		Ret r;
		ubyte mask=0x01;
		foreach(i; nums[0..8]){
			r.n[0]=r.n[0] | (ret.ptr[i] & mask);
			mask=cast(ubyte)(mask<<1);
		}

		mask=0x01;
		foreach(i; nums[8..16]){
			r.n[1]=r.n[1] | (ret.ptr[i] & mask);
			mask=cast(ubyte)(mask<<1);
		}
		
		return r.num;
	}

	static auto getMatchSIMD(ubyte16 control, ubyte check){
		ubyte16 v=check;
		ubyte16 ret=control&v;
		ret=ret-check;
		return ret;
	}

	void add(T el){
		size_t hash=el.hashFunc;
		if(getLoadFactor(addedElements+1)>rehashFactor){
			rehash();
		}
		addedElements++;
		int group=cast(uint)(hash%cast(short)groups.length);
		int groupStart=group;
		//int num;
		//scope(exit)writeln(num);
		while(true){
			Group* gr=&groups[group];
			foreach(i, ubyte used; gr.control.array){
				if(!used){
					Control c;
					c.set(hash);
					gr.control.array[i]=c.b;
					gr.elements[i]=el;
					return;
				}
				//num++;
			}
			//group=(group+1)%cast(uint)groups.length;
			group++;
			if(group>=groups.length){
				group=0;
			}
			assert(group!=groupStart);// Full imposible, remove this?
		}

	}

	uint reszta(size_t hash, size_t num){
		pragma(inline, true);
		uint n=cast(uint)num;
		import std.meta;
		//writeln(num);
		//alias nums=AliasSeq!(2,4,8,16,32,64,128,256,512,1024,2048,4096);
		immutable static uint[] shhh=[0b0,0b1,0b11,0b111,0b1111,0b1111_1,0b1111_11,0b1111_111,0b1111_1111,0b1111_1111_1,0b1111_1111_11,0b1111_1111_111,0b1111_1111_111];
		assert(potega<shhh.length);
		/*writeln("--");
		writeln(num);
		writeln(potega);
		writeln(shhh[potega]);*/
		uint nnn=cast(uint)(hash & shhh.ptr[potega]);
		return nnn;
		/*writeln(nnn);
		switch(n){
			case 1:return 0;
				foreach(d;nums){
					case d:writeln(cast(uint)(hash%d));return cast(uint)(hash%d);

				}
			default:return cast(uint)(hash%n);
		}*/
	}

	import core.stdc.string;
	import core.bitop;

	size_t total;
	size_t totalItera;
	size_t totalIteraGroup;
	bool isIn(T el)nothrow @nogc @system{
		mixin(doNotInline);
		union Helper{
			ubyte16 vec;
			ulong[2] l;
		}

		if(groups.length==0){
			return false;
		}
		//size_t hash=el.hashFunc;
		Hash hash2=Hash(el.hashFunc);
		ubyte h2=hash2.getH2WithLastSet;
		size_t groupsLength=groups.length;
		int group=reszta(hash2.h, groupsLength);
		int groupStart=group;
		Helper help;
		while(true){
			Group* gr=&groups[group];
			help.vec=getMatchSIMD22(gr.control, h2);
			bool ind=0;
			total++;
			while( (help.l[0]!=0) | (help.l[1]!=0)){
				totalItera++;
				if(help.l[ind]==0){
					ind=true;
				}
				int i=(ffsll(help.l[ind])-1)>>3;
				if(gr.elements[i].hashFunc==hash2.h){
					return true;
				}
				help.vec.array[i]=0x00;
			}
			group++;
			if(group>=groupsLength){
				group=0;
			}
			if(group==groupStart){
				return false;
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

	
	foreach(i;1..13){
		map.add(i);		
	}
	foreach(i;1..13){
		assert(map.isIn(i));
	}
	//writeln("asd");
	/*size_t hash=13;
	Hash h=Hash(hash);
	ubyte16 control=h.getH2WithLastSet;
	control.array[3]=23;
	foreach(i;0..1000000){
		doNotOptimize(i);
		auto ret=map.getMatchSIMD(control, h.getH2WithLastSet);
		doNotOptimize(ret);
	}*/
}

void test(){
	HashSet!(int) map;
	byte[int] mapStandard;
	foreach(int i;0..3200){
		map.add(i);
		mapStandard[i]=true;
	}

	enum itNum=10000;
	BenchmarkData!(2, itNum) bench;

	
	ubyte16 bb=0;
	bb.array[14]=23;
	ubyte check=0;
	foreach(i;0..1){
		doNotOptimize(bb);
		//writeln(bb.array);
		auto bbb=map.getMatchSIMD33(bb, check);
		doNotOptimize(bbb);
		//writeln(bbb);
	}

	
	doNotOptimize(map);
	doNotOptimize(mapStandard);
	ubyte aaa;
	foreach(b;0..itNum){
		bench.start!(0)(b);
		foreach(i;0..10000){
			auto ret=map.isIn(aaa);
			aaa+=ret;
			doNotOptimize(ret);
		}
		bench.end!(0)(b);
	}

	aaa=0;
	foreach(b;0..itNum){
		bench.start!(1)(b);
		foreach(i;0..10000){
			auto ret=aaa in mapStandard;
			aaa+=cast(bool)ret;
			doNotOptimize(ret);
		}
		bench.end!(1)(b);
	}

	doNotOptimize(aaa);
	//bench.writeToCsvFile("test.csv",["my", "standard"]);
	bench.plotUsingGnuplot("test.png",["my", "standard"]);

	/*writeln();
	writeln();
	writeln();
	writeln();
	writeln(map.total);
	writeln(map.totalItera);
	writeln(map.totalIteraGroup);*/
}