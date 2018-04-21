/**
Module with multithreaded vectors.
 */
module mutils.container_shared.shared_vector;

import std.algorithm : remove;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;

import mutils.container.vector;

////////////////////

class LockedVectorBuildIn(T){
	T[] array;
public:
	bool empty(){
		return(array.length==0);
	}	
	
	void add( T  t ) {
		synchronized( this ){
			array.assumeSafeAppend~=t;
		}
	}	
	void add( T[]  t ) {
		synchronized( this ){
			array.assumeSafeAppend~=t;
		}
	}
	
	T pop(  ) {
		synchronized( this ){
			if(array.length==0)return T.init;
			T obj=array[$-1];
			array=array.remove(array.length-1);
			return obj;
		}
	}
	
}

class LockedVector(T){
	Vector!T array;
public:
	this(){
		//array=Mallocator.instance.make!(Vector!T)(16);
	}
	~this(){
		//Mallocator.instance.dispose(array);
	}
	bool empty(){
		return(array.length==0);
	}	
	
	void add( T  t ) {
		synchronized( this ){
			array~=t;
		}
	}	
	void add( T[]  t ) {
		synchronized( this ){
			array~=t;
		}
	}
	void removeElement( T elem ) {
		synchronized( this ){
			array.removeElement(elem);
		}
	}
	
	T pop(  ) {
		synchronized( this ){
			if(array.length==0)return T.init;
			T obj=array[$-1];
			array.remove(array.length-1);
			return obj;
		}
	}
	auto opSlice(){
		return array[];
	}

	//allocated by Mallocator.instance
	Vector!T vectorCopy(){
		synchronized( this ){
			Vector!T vec;//=Mallocator.instance.make!(Vector!T)(array.length);
			vec~=array[];
			return vec;
		}
	}
	Vector!T vectorCopyWithReset(){
		if(array.length==0)return Vector!T();
		synchronized( this ){
			scope(exit)array.reset;
			return array.copy;
		}
	}
	
}