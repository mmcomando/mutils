module mutils.container.vector_allocator;

import std.experimental.allocator;
import std.traits;

/**
 * Vector backed by given allocator, it is not releaseing data after destruction, used in lua_json_token to treat dynamic arrays as a custom vector
 **/
struct VectorAllocator(T, Allocator){
	static if(hasStaticMember!(Allocator,"instance")){
		alias allocator=Allocator.instance;
	}else{
		Allocator allocator;
	}

	
	T[] array;

	this(size_t numElements){
		assert(numElements>0);
		setLenght(numElements);
	}


	void clear(){
		removeAll();
	}

	void removeAll(){
		if(array !is null){
			freeData(cast(void[])array);
		}
		array=T[].init;
	}

	bool empty(){
		return (array.length==0);
	}

	size_t length(){
		return array.length;
	}	

	void reset(){
		clear();
	}

	void setLenght(size_t newNumOfElements){
		if( array is null){
			array=allocator.makeArray!(T)(newNumOfElements);
		}else{
			if(array.length<newNumOfElements){
				allocator.expandArray(array, newNumOfElements-array.length);
			}else if(array.length>newNumOfElements){
				allocator.shrinkArray(array, array.length-newNumOfElements);
			}
		}
	}

	void freeData(void[] data){
		allocator.dispose(array);
	}

	void add( T  t ) {
		setLenght(array.length+1);
		array[$-1]=t;
	}

	void add( T[]  t ) {
		size_t sizeBefore=array.length;
		setLenght(array.length+t.length);
		foreach(i;0..t.length){
			array[sizeBefore+i]=t[i];
		}
	}

	
	void remove(size_t elemNum){
		array[elemNum]=array[$-1];
		setLenght(array.length-1);
	}

	void removeElement(T elem){
		foreach(i,ref el;array){
			if(el==elem){
				remove(i);
				return;
			}
		}
	}

	T opIndex(size_t elemNum){
		return array[elemNum];
	}

	auto opSlice(){
		return array;
	}

	T[] opSlice(size_t x, size_t y){
		return array[x..y];
	}

	size_t opDollar(){
		return array.length;
	}

	void opOpAssign(string op)(T obj){
		static assert(op=="~");
		add(obj);
	}

	void opOpAssign(string op)(T[] obj){
		static assert(op=="~");
		add(obj);
	}

	void opIndexAssign(T obj,size_t elemNum){
		array[elemNum]=obj;

	}
	
}
unittest{
	import std.experimental.allocator.mallocator;
	VectorAllocator!(int, Mallocator) vec;
	assert(vec.empty);
	vec.add(0);
	vec.add(1);
	vec.add(2);
	vec.add(3);
	vec.add(4);
	vec.add(5);
	assert(vec.length==6);
	assert(vec[3]==3);
	assert(vec[5]==5);
	assert(vec[]==[0,1,2,3,4,5]);
	assert(!vec.empty);
	vec.remove(3);
	assert(vec.length==5);
	assert(vec[]==[0,1,2,5,4]);//unstable remove

	Mallocator.instance.dispose(vec.array);
}
