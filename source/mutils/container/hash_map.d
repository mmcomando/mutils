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
	union{
		size_t h;
		ubyte[size_t.sizeof] d;
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

	
	static auto getMatchSIMD(ubyte16 control, ubyte check){
		ubyte16 v=check;
		ubyte16 ret=control&v;
		ret=ret-check;
		return ret;
	}

	void add(T el){
		size_t hash=el.hashOf;
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
			foreach(i, ubyte notOk; gr.control.array){
				if(!notOk){
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
		uint n=cast(uint)num;
		import std.meta;
		//writeln(num);
		alias nums=AliasSeq!(2,4,8,16,32,64,128,256,512,1024,2048,4096);
		switch(n){
			case 1:return 0;
				foreach(d;nums){
					case d:return cast(uint)(hash%d);

				}
			default:return cast(uint)(hash%n);
		}
	}

	bool isIn(T el){
		if(groups.length==0){
			return false;
		}
		size_t hash=el.hashOf;
		Hash hash2=Hash(el.hashOf);
		ubyte h2=hash2.getH2WithLastSet;
		//int group=cast(uint)(hash%cast(uint)groups.length);
		//writeln("--");
		int group=reszta(hash,groups.length);
		//writeln(hash,groups.length);
		//writeln(group);

		int groupStart=group;
		while(true){
			Group* gr=&groups[group];
			auto check=getMatchSIMD(gr.control, h2);
			foreach(i, ubyte notOk; check.array){
				if(notOk==0 && gr.elements[i].hashOf==hash){
					return true;
				}
			}
			//group=(group+1)%cast(uint)groups.length;
			group++;
			if(group>=groups.length){
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
		//writeln(i, " ", i.hashOf%map.groups.length, " ", i.hashOf);	
		map.add(i);	
		foreach(gr; map.groups){
			//write(gr.elements);
		}
		//writeln();	
	}
	foreach(i;1..13){
		//writeln("------_");	
		assert(map.isIn(i));
	}

	size_t hash=13;
	Hash h=Hash(hash);
	ubyte16 control=h.getH2WithLastSet;
	control.array[3]=23;
	foreach(i;0..1000000){
		doNotOptimize(i);
		auto ret=map.getMatchSIMD(control, h.getH2WithLastSet);
		doNotOptimize(ret);
	}
}

void test(){
	HashSet!(int) map;
	bool[int] mapStandard;
	foreach(int i;0..32000){
		map.add(i);
		mapStandard[i]=true;
	}

	enum itNum=1000;
	BenchmarkData!(2, itNum) bench;

	

	

	
	doNotOptimize(map);
	doNotOptimize(mapStandard);
	ubyte aaa;
	foreach(b;0..itNum){
		bench.start!(0)(b);
		foreach(i;0..1000){
			auto ret=map.isIn(aaa);
			aaa+=ret;
			doNotOptimize(ret);
		}
		bench.end!(0)(b);
	}

	aaa=0;
	foreach(b;0..itNum){
		bench.start!(1)(b);
		foreach(i;0..1000){
			auto ret=aaa in mapStandard;
			aaa+=cast(bool)ret;
			doNotOptimize(ret);
		}
		bench.end!(1)(b);
	}

	doNotOptimize(aaa);
	//bench.writeToCsvFile("test.csv",["my", "standard"]);
	bench.plotUsingGnuplot("test.png",["my", "standard"]);
}