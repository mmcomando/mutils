module mutils.container.vector;

import core.bitop;
import core.stdc.stdlib : malloc,free;
import core.stdc.string : memset,memcpy;

import std.algorithm: moveEmplace, swap;
import mutils.stdio;

import std.traits: Unqual, isCopyable, TemplateOf;

@nogc @safe nothrow pure size_t nextPow2(size_t num){
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

	this(this){
		writeln("C");
		T[] tmp=array[0..used];
		array=null;
		used=0;
		add(tmp);
	}


	~this() nothrow {
		clear();
	}
	
	void clear(){
		removeAll();
	}
	
	void removeAll(){
		if(array !is null){
			freeData(cast(void[])array);
		}
		array=null;
		used=0;
	}
	
	bool empty(){
		return (used==0);
	}
	
	size_t length(){
		return used;
	}	

	void length(size_t newLength){
		assert(newLength>=used);
		reserve(newLength);
		foreach(ref el;array[used..newLength]){
			el=T.init;
		}
		used=newLength;
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
		auto oldArray=manualExtend(array, newNumOfElements);
		if(oldArray !is null){
			freeData(oldArray);
		}
	}
	
	@nogc void freeData(void[] data){
		writelns("wwwww", T.stringof);
		writeln(array[0..used]);
		// 0xFFFFFF probably invalid value for pointers and other types
		memset(data.ptr,0xFFFFFF0F,data.length);// Makes bugs show up xD 
		free(data.ptr);
	}
	
	static void[] manualExtend(ref T[] array, size_t newNumOfElements=0){
		if(newNumOfElements==0)newNumOfElements=2;
		T[] oldArray=array;
		size_t oldSize=oldArray.length*T.sizeof;
		size_t newSize=newNumOfElements*T.sizeof;
		T* memory=cast(T*)malloc(newSize);
		memcpy(cast(void*)memory,cast(void*)oldArray.ptr,oldSize);
		array=memory[0..newNumOfElements];
		return cast(void[])oldArray;		
	}
	
	Vector!T copy(){
		Vector!T duplicate;
		duplicate.reserve(used);
		duplicate~=array[0..used];
		return duplicate;
	}

	bool canAddWithoutRealloc(uint elemNum=1){
		return used+elemNum<=array.length;
	}
	
	void add(T  t) {
		if(used>=array.length){
			extend(nextPow2(used+1));
		}
		t.moveEmplace(array[used]);
		//array[used]=t;
		used++;
	}

	/// Add element at given position moving others
	void add(T t, size_t pos){
		assert(pos<=used);
		if(used>=array.length){
			extend(array.length*2);
		}
		foreach_reverse(size_t i;pos..used){
			//array[i+1]=array[i];
			swap(array[i+1], array[i]);
		}
		array[pos]=t;
		used++;
	}
	
	void add(T[]  t){
		if(used+t.length>array.length){
			extend(nextPow2(used+t.length));
		}
		foreach(i;0..t.length){
			t[i].moveEmplace(array[used+i]);
			//array[used+i]=t[i];
		}
		used+=t.length;
	}
	
	
	void remove(size_t elemNum){
		//array[elemNum]=array[used-1];
		swap(array[elemNum], array[used-1]);
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
	
	void opIndexAssign(T obj, size_t elemNum){
		assert(elemNum<used, "Range viloation");
		array[elemNum]=obj;		
	}

	void opSliceAssign(T obj, size_t a, size_t b){
		assert(b<used && a<=b, "Range viloation");
		array.ptr[a..b]=obj;		
	}

	bool opEquals()(auto ref const Vector!(T) r) const { 
		return used==r.used && array.ptr[0..used]==r.array.ptr[0..r.used];
	}

	size_t toHash() const nothrow @trusted
	{
		return hashOf(cast( Unqual!(T)[])array.ptr[0..used]);
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

// Helper to avoid GC
private T[n] s(T, size_t n)(auto ref T[n] array) pure nothrow @nogc @safe{return array;}

@nogc nothrow unittest{
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
	assert(vec[]==[0,1,2,3,4,5].s);
	assert(!vec.empty);
	vec.remove(3);
	assert(vec.length==5);
	assert(vec[]==[0,1,2,5,4].s);//unstable remove
	
}

@nogc nothrow unittest{
	Vector!int vec;
	assert(vec.empty);
	vec~=[0,1,2,3,4,5].s;
	assert(vec[]==[0,1,2,3,4,5].s);
	assert(vec.length==6);
	vec~=6;
	assert(vec[]==[0,1,2,3,4,5,6].s);
	
}


@nogc nothrow unittest{
	Vector!int vec;
	vec~=[0,1,2,3,4,5].s;
	vec[3]=33;
	assert(vec[3]==33);
	
}