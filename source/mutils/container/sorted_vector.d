module mutils.container.sorted_vector;

import std.algorithm:sort;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.functional:binaryFun;

import mutils.container.vector;

/***
 * Vector which keeps data sorted
 */
struct SortedVector(T, alias less="a < b")
{
	alias cmpFunction=binaryFun!less;
	Vector!T vec;

	bool empty(){
		return (vec.used==0);
	}
	
	size_t length(){
		return vec.used;
	}	
	
	void reset(){
		vec.used=0;
	}

	void clear(){
		vec.clear();
	}

	size_t add(T t){
		foreach(i, el;vec[]){
			if(cmpFunction(t,el)){
				vec.add(t, i);
				return i;
			}
		}
		size_t addPos=vec.length;
		vec.add(t, addPos);
		return addPos;
	}

	void add( T[]  t ) {
		T[8] tmpMemory;
		Vector!T tmp;
		T[] slice;

		if(t.length<=8){
			tmpMemory[0..t.length]=t;
			slice=tmpMemory[0..t.length];
		}else{
			tmp.add(t);
			slice=tmp[];
		}
		sort!(cmpFunction)(slice);
		vec.reserve(vec.length+t.length);
		size_t lastInsertIndex=vec.length;
		foreach_reverse(elNum, elToAdd;slice){
			size_t posToInsert=lastInsertIndex;
			foreach_reverse(i, el;vec.array[0..lastInsertIndex]){
				if(cmpFunction(elToAdd, el)){
					posToInsert=i;
				}
			}
			foreach_reverse(i; posToInsert..lastInsertIndex){
				vec.array[elNum+i+1]=vec.array[i];
			}
			vec.array[posToInsert+elNum]=elToAdd;
			lastInsertIndex=posToInsert;
		}

		vec.used+=t.length;
		tmp.removeAll();
	}

	void remove(size_t elemNum){
		vec.removeStable(elemNum);
	}

	void opOpAssign(string op)(T obj){
		static assert(op=="~");
		add(obj);
	}
	
	void opOpAssign(string op)(T[] obj){
		static assert(op=="~");
		add(obj);
	}

	ref T opIndex(size_t elemNum){
		return vec.array[elemNum];
	}
	
	auto opSlice(){
		return vec.array[0..vec.used];
	}
	
	T[] opSlice(size_t x, size_t y){
		return vec.array[x..y];
	}
	
	size_t opDollar(){
		return vec.used;
	}
}

// Helper to avoid GC
private T[n] s(T, size_t n)(auto ref T[n] array) pure nothrow @nogc @safe{return array;}

unittest{
	SortedVector!int vector;
	assert(vector.add(5)==0);
	assert(vector.add(3)==0);
	assert(vector.add(6)==2);
	assert(vector[]==[3,5,6].s);

	vector.add([2,4,7].s);
	assert(vector[]==[2,3,4,5,6,7].s);
	vector.add(vector[]);
	vector.add(vector[]);
	assert(vector[]==[2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7, 7].s);
}
