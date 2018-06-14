module mutils.container.hash_map_simd;

import mutils.container.hash_set_simd;

struct HashMap(KeyTypeE, T){
	alias Key=KeyTypeE;
	alias Value=T;

	HashSet!(Key, defaultHashFunc, Value) set;

	void add(Key k, T v){
		size_t index=set.getIndex(k);
		if(index==set.getIndexEmptyValue){
			set.add(k, v);
		}else{
			size_t group=index/8;
			size_t elIndex=index%8;
			set.groups[group].values[elIndex]=v;
		}
	}

	void clear(){
		set.clear();
	}
	
	void reset(){
		set.reset();
	}
	
	size_t length(){
		return set.length;
	}

	bool tryRemove(Key k){	
		return set.tryRemove(k);
	}

	void remove(Key k){
		set.remove(k);
	}

	bool isIn(Key k){
		size_t index=set.getIndex(k);
		return index!=set.getIndexEmptyValue;		
	}

	ref T get(Key k){
		size_t index=set.getIndex(k);
		assert(index!=set.getIndexEmptyValue);
		size_t group=index/8;
		size_t elIndex=index%8;
		return set.groups[group].values[elIndex];

	}

	T getDefault(Key k, T defaultValue){
		size_t index=set.getIndex(k);
		if(index==set.getIndexEmptyValue){
			return defaultValue;
		}else{
			size_t group=index/8;
			size_t elIndex=index%8;
			return set.groups[group].values[elIndex];
		}		
	}

	ref T getDefault(Key k, ref T defaultValue){
		size_t index=set.getIndex(k);
		if(index==set.getIndexEmptyValue){
			return defaultValue;
		}else{
			size_t group=index/8;
			size_t elIndex=index%8;
			return set.groups[group].values[elIndex];
		}		
	}

	ref T getInsertDefault(Key k, T defaultValue){		
		size_t index=set.getIndex(k);
		if(index==set.getIndexEmptyValue){
			set.add(k, defaultValue);
		}
		index=set.getIndex(k);
		assert(index!=set.getIndexEmptyValue);
		size_t group=index/8;
		size_t elIndex=index%8;
		return set.groups[group].values[elIndex];
				
	}

	int byKey(scope int delegate(Key k) dg){
		int result;
		foreach(ref Key k;set){
			result=dg(k);
			if (result)
				break;	
		}
		return result;		
	}

	int byValue(scope int delegate(ref T k) dg){
		int result;
		foreach(ref Control c, ref Key k, ref Value v; set){
			result=dg(v);
			if (result)
				break;	
		}
		return result;		
	}

	int byKeyValue(scope int delegate(ref Key k, ref Value k) dg){
		int result;
		foreach(ref Control c, ref Key k, ref Value v; set){
			result=dg(k, v);
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
		foreach(ref k, ref v; &byKeyValue){
			formatValue(sink, k, fmt);
			formatValue(sink, ':', fmt);
			formatValue(sink, v, fmt);
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
	foreach(k, v; &map.byKeyValue){}
	foreach(v; &map.byValue){}

}