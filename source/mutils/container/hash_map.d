module mutils.container.hash_map;

import std.stdio;
import mutils.container.hash_set;

struct HashMap(Key, T){
	alias KeyType=Key;
	alias ValueType=T;
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

		size_t index=set.getIndex(kv);
		if(index==set.getIndexEmptyValue){
			set.add(kv);
		}else{
			size_t group=index/8;
			size_t elIndex=index%8;
			set.groups[group].elements[elIndex].value=v;
		}
	}
	
	size_t length(){
		return set.length;
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
		size_t index=set.getIndex(kv);
		return index!=set.getIndexEmptyValue;		
	}

	T get(Key k){
		KeyValue kv=KeyValue(k);
		
		size_t index=set.getIndex(kv);
		assert(index!=set.getIndexEmptyValue);
		size_t group=index/8;
		size_t elIndex=index%8;
		return set.groups[group].elements[elIndex].value;

	}

	T getDefault(Key k, T defaultValue){
		KeyValue kv=KeyValue(k);
		
		size_t index=set.getIndex(kv);
		if(index==set.getIndexEmptyValue){
			return defaultValue;
		}else{
			size_t group=index/8;
			size_t elIndex=index%8;
			return set.groups[group].elements[elIndex].value;
		}
		
	}

	T getInsertDefault(Key k, T defaultValue){
		KeyValue kv=KeyValue(k);
		
		size_t index=set.getIndex(kv);
		if(index==set.getIndexEmptyValue){
			kv.value=defaultValue;
			set.add(kv);
			return defaultValue;
		}else{
			size_t group=index/8;
			size_t elIndex=index%8;
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

	int byValue(scope int delegate(ref T k) dg){
		int result;
		foreach(ref KeyValue kv;set){
			result=dg(kv.value);
			if (result)
				break;	
		}
		return result;		
	}

	int byKeyValue(scope int delegate(ref KeyValue k) dg){
		int result;
		foreach(ref KeyValue kv;set){
			result=dg(kv);
			if (result)
				break;	
		}
		return result;		
	}

	import std.format:FormatSpec,formatValue;
	/**
	 * Preety print
	 */
	void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt)
	{
		formatValue(sink, '[', fmt);
		foreach(kv; &byKeyValue){
			formatValue(sink, kv.key, fmt);
			formatValue(sink, ':', fmt);
			formatValue(sink, kv.value, fmt);
			formatValue(sink, ", ", fmt);
		}
		formatValue(sink, ']', fmt);
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