/**
Containers used to store Fiber objects.
Allocating new Fiber is expensive so need for this containers.
There are few implementations which can be easly changed and tested for performance or correctness.
*/
module mutils.job_manager.fiber_cache;

import core.stdc.stdlib:malloc,free;
import core.stdc.string:memset,memcpy;
import core.atomic;
import core.thread:Fiber,Thread,PAGESIZE;
import core.memory;

import mutils.job_manager.shared_utils;

//only one warning about GC
Fiber newFiber(){
	static void dummy(){}
	Fiber fiber = new Fiber(&dummy,PAGESIZE * 32u);
	GC.addRoot(cast(void*)fiber);	
	fiber.call();
	return fiber;
}

///returns data if it is marked as unused, if there is no space realocates
class FiberVectorCache{
	alias T=Fiber;
	static  struct DataStruct{ 
		bool used;
		T data;		
	}
	alias LoType=ulong;
	align (64)shared DataStruct[] dataArray;
	align (64)shared LoType loaders;
	shared uint dataGot;
	shared uint dataRemoved;

	this(uint length=128){
		assert(length>0);
		dataArray=extendArray(length,dataArray);
	}

	~this(){}

	void clear(){
		synchronized(this){
			auto localSlice=atomicLoad(dataArray);
			atomicStore(dataArray,null);
			while(atomicLoad(loaders)!=0){}
			if(localSlice.length!=0){
				GC.removeRange(cast(DataStruct*)localSlice.ptr);
				free(cast(DataStruct*)localSlice.ptr);
			}
			atomicStore(dataArray,extendArray(1,dataArray));
		}
	}

	T initVar(){
		Fiber fiber = newFiber();
		return fiber;
	}

	shared(DataStruct[])  extendArray(uint length,shared DataStruct[] oldDataArray){
		DataStruct[] array;
		assert(length>oldDataArray.length);

		uint size=cast(uint)DataStruct.sizeof*length;
		uint oldSize=cast(uint)(DataStruct.sizeof*oldDataArray.length);
		DataStruct* memory=cast(DataStruct*)malloc(size);
		GC.addRange(memory, size);
		memset(memory,0,size);//TODO can fill only part
		memcpy(memory,cast(DataStruct*)oldDataArray.ptr,oldSize);
		array=cast(shared DataStruct[])memory[0 .. length];

		foreach(ref data;array[oldDataArray.length .. length]){
			data.data=initVar();
		}

		if(oldDataArray.length!=0){
			GC.removeRange(cast(DataStruct*)oldDataArray.ptr);
			memset(cast(DataStruct*)oldDataArray.ptr,0,oldSize);//for better crashes
			free(cast(DataStruct*)oldDataArray.ptr);
		}
		return cast(shared DataStruct[])array;
	}

	T getData(uint thread=0,uint threadCount=1){
		atomicOp!"+="(dataGot, 1);
		//try to find free slot with atmoics
		{
			atomicOp!"+="(loaders, cast(LoType)1);
			scope(exit)atomicOp!"-="(loaders, cast(LoType)1);
			auto localSlice=atomicLoad(dataArray);
			uint division=(cast(uint)localSlice.length/threadCount)*thread;

			foreach(uint i,ref data;localSlice[division..$]){
				if(data.used==false){
					bool isEmpty=cas(&data.used,false,true);
					if(isEmpty){
						return cast(Fiber)data.data;
					}
				}
			}
			foreach(uint i,ref data;localSlice[0..division]){
				if(data.used==false){
					bool isEmpty=cas(&data.used,false,true);
					if(isEmpty){
						return cast(Fiber)data.data;
					}
				}
			}
		}
		//find free slot or extend array
		synchronized(this){
			auto sliceCopy=dataArray;
			atomicStore(dataArray,null);//stop all who is getting data without a lock
			while(atomicLoad(loaders)!=0){}//wait for them

			//try to find free slot with mutex
			foreach(uint i,ref data;sliceCopy){
				if(data.used==false){
					data.used=true;
					atomicStore(dataArray,sliceCopy);
					return cast(T)atomicLoad(dataArray[i].data);
				}
			}
			//all slots used
			//extend array
			auto newArray=extendArray(cast(uint)sliceCopy.length*2,sliceCopy);
			auto freeIndex=sliceCopy.length;
			newArray[freeIndex].used=true;
			atomicStore(dataArray,newArray);
			return cast(T)newArray[freeIndex].data;
		}
	}

	void removeData(T elementToDelete,uint thread=0,uint threadCount=1){
		atomicOp!"+="(dataRemoved, 1);
		{
			atomicOp!"+="(loaders, cast(LoType)1);
			scope(exit)atomicOp!"-="(loaders, cast(LoType)1);
			auto localSlice=atomicLoad(dataArray);
			uint division=(cast(uint)localSlice.length/threadCount)*thread;
			foreach(uint i,ref data;localSlice[division..$]){
				if(cast(Fiber)data.data==elementToDelete){
					atomicStore(data.used, false);
					return;
				}
			}
			foreach(uint i,ref data;localSlice[0..division]){
				if(cast(Fiber)data.data==elementToDelete){
					atomicStore(data.used, false);
					return;
				}
			}
		}
		synchronized(this){
			auto localSlice=atomicLoad(dataArray);
			foreach(uint i,ref data;localSlice){
				if(cast(Fiber)data.data==elementToDelete){
					atomicStore(data.used, false);
					return;
				}
			}
		}
	}
}

class FiberNoCache{

	Fiber getData(uint,uint){
		Fiber fiber = newFiber();		
		return fiber;
	}

	void removeData(Fiber obj,uint,uint){
		GC.removeRoot(cast(void*)obj);
	}

}

class FiberOneCache{
	static void dummy(){}
	
	static Fiber lastFreeFiber;//1 element tls cache
	
	Fiber getData(uint,uint){
		Fiber fiber;
		if(lastFreeFiber is null){
			fiber = newFiber();
		}else{
			fiber=lastFreeFiber;
			lastFreeFiber=null;
		}
		return fiber;
	}

	void removeData(Fiber obj,uint,uint){
		if(lastFreeFiber !is null){
			GC.removeRoot(cast(void*)lastFreeFiber);
			Mallocator.instance.dispose(lastFreeFiber);
		}
		lastFreeFiber=obj;
	}
}

import mutils.container.vector;
static Vector!Fiber array;
static uint used=0;

void initializeFiberCache(){
	array.reserve(16);
}

class FiberTLSCache{

	this(){}
	
	Fiber getData(uint,uint){
		Fiber fiber;
		if(array.length<=used){
			fiber= newFiber();
			array~=fiber;
			used++;
			return fiber;
		}
		fiber=array[used];
		used++;
		return fiber;
	}

	void removeData(Fiber obj,uint,uint){
		foreach(i,fiber;array){
			if(obj == fiber){
				array[i]=array[used-1];
				array[used-1]=obj;
				used--;
				return;
			}
		}
		assert(0);
	}
}




import mutils.benchmark;
import std.stdio:writefln,writeln;
import std.random:randomShuffle;
import std.conv:to;



//test extend
unittest{
	FiberVectorCache vec=new FiberVectorCache(1);assert(vec.dataArray.length==1);
	vec.dataArray=vec.extendArray(2,vec.dataArray);assert(vec.dataArray.length==2);
	vec.dataArray=vec.extendArray(3,vec.dataArray);assert(vec.dataArray.length==3);
	vec.dataArray=vec.extendArray(4,vec.dataArray);assert(vec.dataArray.length==4);
	vec.dataArray=vec.extendArray(50,vec.dataArray);assert(vec.dataArray.length==50);
}

//test get + extend
unittest{
	alias T=Fiber;
	FiberVectorCache vec=new FiberVectorCache(10);
	T var;
	foreach(i;0..10){
		var=vec.getData();assert(vec.dataArray.length==10);
	}
	var=vec.getData();assert(vec.dataArray.length==20);
}
void dummyCall(){}
//test multithreaded
void testCV(){
	shared uint sum;
	FiberVectorCache vec=Mallocator.instance.make!FiberVectorCache(1);
	scope(exit)Mallocator.instance.dispose(vec);
	immutable uint firstLoop=10000;
	immutable uint secondLoop=8;
	void testGet(){
		uint threadNum=Thread.getThis.name.to!uint;
		uint numGot;
		foreach(i;0..firstLoop){
			vec.clear();
			uint rand=secondLoop;
			foreach(j;0..rand){
				auto data=vec.getData();
			}
			numGot+=rand;
		}
		atomicOp!"+="(sum, numGot);
	}
	void testGet2(){
		uint threadNum=Thread.getThis.name.to!uint;
		uint numGot;
		foreach(i;0..firstLoop){
			vec.clear();
			uint rand=secondLoop;
			foreach(j;0..rand){
				auto data=vec.getData(threadNum,16);
			}
			numGot+=rand;
		}
		atomicOp!"+="(sum, numGot);
	}
	void testRemove(){
		uint threadNum=Thread.getThis.name.to!uint;
		uint numGot;
		Fiber[secondLoop] arr;
		foreach(i;0..firstLoop){
			uint rand=secondLoop;
			foreach(j;0..rand){
				arr.ptr[j]=vec.getData();
			}
			foreach(j;0..rand){
				foreach(k;0..100){
					arr.ptr[j].reset(&dummyCall);
					arr.ptr[j].call();
				}
			}
			randomShuffle(arr[0..rand]);
			foreach(j;0..rand){
				vec.removeData(arr.ptr[j]);
			}
			numGot+=rand;
		}
		atomicOp!"+="(sum, numGot);
	}
	void testRemove2(){
		uint threadNum=Thread.getThis.name.to!uint;
		uint numGot;
		Fiber[secondLoop] arr;
		foreach(i;0..firstLoop){
			uint rand=secondLoop;
			foreach(j;0..rand){
				arr.ptr[j]=vec.getData(threadNum,16);
			}
			
			randomShuffle(arr[0..rand]);
			foreach(j;0..rand){
				vec.removeData(arr.ptr[j],threadNum,16);
			}
			numGot+=rand;
		}
		atomicOp!"+="(sum, numGot);
	}

	{ 
		StopWatch sw;
		sw.start();
		vec.dataGot=0;
		testMultithreaded(&testGet,16);
		sw.stop();
		assert(vec.dataGot==sum);
		
		writefln( "G1 Benchmark: %s %s[ms], %s[it/ms]",vec.dataGot,sw.msecs,vec.dataGot/sw.msecs);
		vec.clear();
	}

	{ 
		StopWatch sw;
		sw.start();
		sum=0;
		vec.dataGot=0;
		testMultithreaded(&testGet2,16);
		sw.stop();  
		assert(vec.dataGot==sum);

		writefln( "G2 Benchmark: %s %s[ms], %s[it/ms]",vec.dataGot,sw.msecs,vec.dataGot/sw.msecs);
		vec.clear();
	}
	{
		StopWatch sw;
		sw.start();
		sum=0;
		vec.dataGot=0;
		vec.dataRemoved=0;
		testMultithreaded(&testRemove,16);
		sw.stop();  
		foreach(i,data;vec.dataArray){
			assert(!data.used);
		}
		writefln( "R1 Benchmark: %s %s[ms], %s[it/ms]",sum,sw.msecs,sum/sw.msecs);
	}
	{
		//GC.disable;
		StopWatch sw;
		sw.start();
		sum=0;
		vec.dataGot=0;
		vec.dataRemoved=0;
		testMultithreaded(&testRemove2,16);
		sw.stop();  
		foreach(i,data;vec.dataArray){
			assert(!data.used);
		}
		writeln(vec.dataGot);
		writeln(vec.dataArray.length);
		writefln( "R2 Benchmark: %s %s[ms], %s[it/ms]",sum,sw.msecs,sum/sw.msecs);
	}
}
unittest{
	//testCV();
}