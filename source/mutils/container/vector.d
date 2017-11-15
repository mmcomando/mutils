module mutils.container.vector;

import core.bitop;
import core.stdc.stdlib : malloc,free;
import core.stdc.string : memset,memcpy;

@nogc @safe nothrow size_t nextPow2(size_t num){
	return 1<< bsr(num)+1;
}


struct Vector(T){
	T[] array;
	size_t used;
public:

	this(T t){
		add(t);
	}

	this(T[] t){
		add(t);
	}

	this(size_t numElements){
		assert(numElements>0);
		extend(numElements);
	}
	
	void clear(){
		removeAll();
	}
	
	void removeAll(){
		if(array !is null){
			freeData(cast(void[])array);
		}
		array=T[].init;
		used=0;
	}
	
	bool empty(){
		return (used==0);
	}
	
	size_t length(){
		return used;
	}	
	
	void reset(){
		used=0;
	}

	
	void reserve(size_t numElements){
		if(numElements>array.length){
			extend(numElements);
		}
	}

	size_t capacity(){
		return array.length-used;
	}
	
	void extend(size_t newNumOfElements){
		auto oldArray=manualExtend(newNumOfElements);
		if(oldArray !is null){
			freeData(oldArray);
		}
	}
	
	@nogc void freeData(void[] data){
		//0xFFFFFF probably invalid value for pointers and other types
		memset(cast(void*)data.ptr,0xFFFFFFFF,data.length);//very important :) makes bugs show up xD 
		free(data.ptr);
	}
	
	void[] manualExtend(size_t newNumOfElements=0){
		if(newNumOfElements==0)newNumOfElements=2;
		T[] oldArray=array;
		size_t oldSize=oldArray.length*T.sizeof;
		size_t newSize=newNumOfElements*T.sizeof;
		//T[] memory=mallocator.makeArray!(T)(newNumOfElements);
		//memcpy(cast(void*)memory.ptr,cast(void*)oldArray.ptr,oldSize);
		//array=memory;
		T* memory=cast(T*)malloc(newSize);
		memcpy(cast(void*)memory,cast(void*)oldArray.ptr,oldSize);
		array=memory[0..newNumOfElements];
		return cast(void[])oldArray;
		
	}
	bool canAddWithoutRealloc(uint elemNum=1){
		return used+elemNum<=array.length;
	}
	
	void add(T  t) {
		if(used>=array.length){
			extend(nextPow2(used+1));
		}
		array[used]=t;
		used++;
	}

	///Add element at given position moving others
	void add(T t, size_t pos){
		assert(pos<=used);
		if(used>=array.length){
			extend(array.length*2);
		}
		foreach_reverse(size_t i;pos..used){
			array[i+1]=array[i];
		}
		array[pos]=t;
		used++;
	}
	
	void add(T[]  t) {
		if(used+t.length>array.length){
			extend(nextPow2(used+t.length));
		}
		foreach(i;0..t.length){
			array[used+i]=t[i];
		}
		used+=t.length;
	}
	
	
	void remove(size_t elemNum){
		array[elemNum]=array[used-1];
		used--;
	}
	
	bool tryRemoveElement(T elem){
		foreach(i,ref el;array[0..used]){
			if(el==elem){
				remove(i);
				return true;
			}
		}
		return false;
	}
	
	void removeElement(T elem){
		assert(tryRemoveElement(elem));
	}
	
	ref T opIndex(size_t elemNum){
		pragma(inline, true);
		assert(elemNum<used);
		return array.ptr[elemNum];
	}
	
	auto opSlice(){
		return array.ptr[0..used];
	}
	
	T[] opSlice(size_t x, size_t y){
		assert(y<=used);
		return array.ptr[x..y];
	}
	
	size_t opDollar(){
		return used;
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
		assert(elemNum<used);
		array[elemNum]=obj;
		
	}


	import std.format:FormatSpec,formatValue;
	/**
	 * Preety print
	 */
	void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt)
	{
		static if(__traits(compiles,formatValue(sink, array[0..used], fmt))){
			formatValue(sink, array[0..used], fmt);
		}
	}
	
}
unittest{
	Vector!int vec;
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
	
}

unittest{
	Vector!int vec;
	assert(vec.empty);
	vec~=[0,1,2,3,4,5];
	assert(vec[]==[0,1,2,3,4,5]);
	assert(vec.length==6);
	vec~=6;
	assert(vec[]==[0,1,2,3,4,5,6]);
	
}


unittest{
	Vector!int vec;
	vec~=[0,1,2,3,4,5];
	vec[3]=33;
	assert(vec[3]==33);
	
}