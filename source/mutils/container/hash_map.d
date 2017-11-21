﻿module mutils.container.hash_map;

import std.stdio;
import mutils.container.hash_set;

struct HashMap(Key, T){
	struct KeyValue{
		Key key;
		T value;

		bool opEquals()(auto ref const KeyValue r) const { 
			return key==r.key;
		}
	}

	static size_t hashFunc(KeyValue kv){
		return defaultHashFunc(kv.key);
	}

	HashSet!(KeyValue, hashFunc) set;

	void add(Key k, T v){
		KeyValue kv=KeyValue(k, v);

		uint index=set.getIndex(kv);
		if(index==uint.max){
			set.add(kv);
		}else{
			int group=index/16;
			int elIndex=index%16;
			set.groups[group].elements[elIndex].value=v;
		}
	}

	bool tryRemove(Key k){
		KeyValue kv=KeyValue(k);		
		return set.tryRemove(kv);
	}

	void remove(Key k){
		KeyValue kv=KeyValue(k);		
		set.remove(kv);
	}

	bool isIn(Key k){
		KeyValue kv=KeyValue(k);		
		uint index=set.getIndex(kv);
		return index!=uint.max;		
	}

	T get(Key k){
		KeyValue kv=KeyValue(k);
		
		uint index=set.getIndex(kv);
		assert(index!=uint.max);
		int group=index/16;
		int elIndex=index%16;
		return set.groups[group].elements[elIndex].value;

	}

	T getDefault(Key k, T defaultValue){
		KeyValue kv=KeyValue(k);
		
		uint index=set.getIndex(kv);
		if(index==uint.max){
			return defaultValue;
		}else{
			int group=index/16;
			int elIndex=index%16;
			return set.groups[group].elements[elIndex].value;
		}
		
	}

	T getInsertDefault(Key k, T defaultValue){
		KeyValue kv=KeyValue(k);
		
		uint index=set.getIndex(kv);
		if(index==uint.max){
			kv.value=defaultValue;
			set.add(kv);
			return defaultValue;
		}else{
			int group=index/16;
			int elIndex=index%16;
			return set.groups[group].elements[elIndex].value;
		}		
	}

	int byKey(scope int delegate(Key k) dg){
		int result;
		foreach(ref KeyValue kv;set){
			result=dg(kv.key);
			if (result)
				break;	
		}
		return result;		
	}

	int byValue(scope int delegate(T k) dg){
		int result;
		foreach(ref KeyValue kv;set){
			result=dg(kv.value);
			if (result)
				break;	
		}
		return result;		
	}

	int byKeyValue(scope int delegate(KeyValue k) dg){
		int result;
		foreach(ref KeyValue kv;set){
			result=dg(kv);
			if (result)
				break;	
		}
		return result;		
	}
}

unittest{
	HashMap!(int, int) map;
	map.add(1, 10);
	assert(map.get(1)==10);
	assert(map.getDefault(2, 20)==20);
	assert(!map.isIn(2));
	assert(map.getInsertDefault(2, 20)==20);
	assert(map.get(2)==20);
	foreach(k; &map.byKey){}
	foreach(kv; &map.byKeyValue){}
	foreach(v; &map.byValue){}

}