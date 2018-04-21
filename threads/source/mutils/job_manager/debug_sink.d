/**
Module used to efficiently store simple data from many threads.
May be used for validation multithreaded algorithms.
Ex. multithreaded executes 1000 jobs, each jobs adds to sink unique number.
After execution if in this sink are all 1000 numbers and all are unique everything was ok.
*/

module mutils.job_manager.debug_sink;


import std.experimental.allocator;
import std.experimental.allocator.mallocator;

import mutils.container_shared.shared_vector;
import mutils.job_manager.utils;



import mutils.container.vector;

class DebugSink{
	alias T=int;


	alias DataVector=Vector!T;
	static DataVector vector;

	alias DataDataVector=LockedVector!(DataVector*);
	__gshared DataDataVector allData;


	static void initialize(){
		//vector=Mallocator.instance.make!DataVector;
		allData.add(&vector);
	}

	static void deinitialize(){
		allData.removeElement(&vector);
		//Mallocator.instance.dispose(vector);
	}
	
	
	static void initializeShared(){
		allData=Mallocator.instance.make!DataDataVector;
	}

	static void deinitializeShared(){
		Mallocator.instance.dispose(allData);
	}

	static void add(T obj){
		vector~=obj;
	}

	static void reset(){
		foreach(ref arr;allData){
			arr.reset();
		}
	}
	
	static auto getAll(){
		return allData;
	}

	static verifyUnique(int expectedNum){
		import std.algorithm;
		auto all=DebugSink.getAll()[];
		auto oneRange=all.map!((a) => (*a)[]).joiner;
		Vector!int allocated;
		foreach(int num; oneRange){
			allocated~=num;
		}
		allocated[].sort();
		assertM(allocated.length, expectedNum);
		Vector!int allocatedCopy;

		foreach(int num; allocated[].uniq()){
			allocatedCopy~=num;
		}
		size_t dt=allocated.length-allocatedCopy.length;
		assertM(allocatedCopy.length ,expectedNum);
	}
}


