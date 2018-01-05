/**
Module  contains multithreated allcoators. Few of them with similar interface.
 */
module mutils.container_shared.shared_allocator;

import std.stdio;
import std.conv:emplace;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;

import mutils.job_manager.shared_utils;
import mutils.job_manager.utils;
import mutils.container.vector;


class MyMallocator{
	shared Mallocator allocator;
	this(){
		allocator=Mallocator.instance;
	}
	auto make(T,Args...)(auto ref Args args){
		return allocator.make!T(args);
	}
	void dispose(T)(ref T* obj){
		allocator.dispose(obj);
		//obj=T.init;
	}
}
class MyGcAllcoator{
	auto make(T,Args...)(auto ref Args args){
		auto var=new T(args);
		import core.memory;
		GC.addRoot(var);
		return var;
	}
	void dispose(T)(ref T* obj){
		import core.memory;
		GC.removeRoot(obj);
		//obj=T.init;
	}
}

import core.atomic;
import std.random:uniform;



class BucketAllocator(uint bucketSize){
	static assert(bucketSize>=8);
	enum shared Bucket* invalidValue=cast(shared Bucket*)858567;
	
	static struct Bucket{
		union{
			void[bucketSize] data;
			Bucket* next;
		}
	}
	enum bucketsNum=128;
	
	
	static struct BucketsArray{
	@nogc:
		Bucket[bucketsNum] buckets;
		shared Bucket* empty;
		void initialize() shared {
			shared Bucket* last;
			foreach(i,ref bucket;buckets){
				bucket.next=last;
				last=&bucket;
			}
			empty=cast(shared Bucket*)last;
		}
		uint freeSlots()shared {
			uint i;
			shared Bucket* slot=empty;
			while(slot !is null){
				i++;
				slot=slot.next;
			}
			return i;
		}
		uint usedSlots()shared {
			return bucketsNum-freeSlots;
		}
	}
	alias BucketArraysType=Vector!(shared BucketsArray*);
	
	//shared BucketsArray*[] bucketArrays;
	BucketArraysType bucketArrays;
	
	
	this(){
		//bucketArrays=Mallocator.instance.make!(BucketArraysType);
		bucketArrays.extend(128);
	}
	~this(){
	}
	void[] oldData;
	void extend(){
		//shared BucketsArray* arr=new shared BucketsArray;
		shared BucketsArray* arr=cast(shared BucketsArray*)Mallocator.instance.make!(BucketsArray);
		(*arr).initialize();
		if(!bucketArrays.canAddWithoutRealloc){
			if(oldData !is null){
				bucketArrays.freeData(oldData);//free on next alloc, noone should use the old array
			}
			oldData=bucketArrays.manualExtend(bucketArrays.array);
		}
		bucketArrays~=arr;
	}
	T* make(T,Args...)(auto ref Args args){
		void[] memory=allocate();
		//TODO some checks: aligment, size, itp??
		return memory.emplace!(T)( args );
	}
	void[] allocate(){
	FF:foreach(i,bucketsArray;bucketArrays){
			if(bucketsArray.empty is null)continue;
			
			shared Bucket* emptyBucket;
			do{
			BACK:
				emptyBucket=atomicLoad(bucketsArray.empty);
				if(emptyBucket is null){
					continue FF;
				}
				if(emptyBucket==invalidValue){
					goto BACK;
				}
			}while(!cas(&bucketsArray.empty,emptyBucket,invalidValue));
			atomicStore(bucketsArray.empty,emptyBucket.next);
			return cast(void[])emptyBucket.data;
		}
		
		//assert(0);
		synchronized(this){
			extend();
			auto bucketsArray=bucketArrays[$-1];
			shared Bucket* empty=bucketsArray.empty;
			bucketsArray.empty=(*bucketsArray.empty).next;
			return 	cast(void[])empty.data;		
		}
		
	}
	void dispose(T)(T* obj){
		deallocate(cast(void[])obj[0..1]);
	}
	void deallocate(void[] data){
		foreach(bucketsArray;bucketArrays){
			auto ptr=bucketsArray.buckets.ptr;
			auto dptr=data.ptr;
			if(dptr>=ptr+bucketsNum || dptr<ptr){
				continue;
			}
			shared Bucket* bucket=cast(shared Bucket*)data.ptr;
			shared Bucket* emptyBucket;
			
			do{
			BACK:
				emptyBucket=atomicLoad(bucketsArray.empty);
				if(emptyBucket==invalidValue){
					goto BACK;
				}
				bucket.next=emptyBucket;
			}while(!cas(&bucketsArray.empty,emptyBucket,bucket));
			return;
		}
		writelnng(data.ptr);
		assert(0);
	}
	
	uint usedSlots(){
		uint sum;
		foreach(bucketsArray;bucketArrays)sum+=bucketsArray.usedSlots;
		return sum;
		
	}
}



void ttt(){
	BucketAllocator!(64) allocator=Mallocator.instance.make!(BucketAllocator!64);
	scope(exit)Mallocator.instance.dispose(allocator);
	foreach(k;0..123){
		void[][] memories;
		assert(allocator.bucketArrays[0].freeSlots==allocator.bucketsNum);
		foreach(i;0..allocator.bucketsNum){
			memories~=allocator.allocate();
		}
		assert(allocator.bucketArrays[0].freeSlots==0);
		foreach(i;0..allocator.bucketsNum){
			memories~=allocator.allocate();
			assert(allocator.bucketArrays.length==2);
		}
		foreach(i,m;memories){
			allocator.deallocate(m);
		}
	}
	
}
import mutils.benchmark;
void testAL(){
	BucketAllocator!(64) allocator=Mallocator.instance.make!(BucketAllocator!(64));
	scope(exit)Mallocator.instance.dispose(allocator);
	shared ulong sum;
	void test(){
		foreach(k;0..1000){
			int*[] memories;
			uint rand=uniform(130,140);
			memories=Mallocator.instance.makeArray!(int*)(rand);
			scope(exit)Mallocator.instance.dispose(memories);
			foreach(i;0..rand){
				memories[i]=allocator.make!int();
			}
			foreach(m;memories){
				allocator.dispose(m);
			}
			atomicOp!"+="(sum,memories.length);
		}
	}
	void testAdd(){
		foreach(i;0..128){
			allocator.allocate();
		}
	}
	foreach(i;0..10000){
		sum=0;
		StopWatch sw;
		sw.start();
		testMultithreaded(&test,16);
		sw.stop();  	
		writefln( "Benchmark: %s %s[ms], %s[it/ms]",sum,sw.msecs,sum/sw.msecs);
		
		assert(allocator.usedSlots==0);
	}
	
}
unittest{
	//testAL();
}