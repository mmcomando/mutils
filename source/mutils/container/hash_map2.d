module mutils.container.hash_map2;

//import std.meta;
import std.traits;

import mutils.benchmark;
import mutils.container.vector;
import mutils.traits;


import std.stdio: writefln, writeln;

private enum HASH_EMPTY = 0;
private enum HASH_DELETED = 0x1;
private enum HASH_FILLED_MARK = ulong(1) << 8 * ulong.sizeof - 1;

size_t defaultHashFunc(T)(auto ref T t){
	static if (isIntegral!(T)){
		return hashInt(t);
	}else{
		return hashInt(t.hashOf);// hashOf is not giving proper distribution between H1 and H2 hash parts
	}
}

// Can turn bad hash function to good one
ulong hashInt(ulong x) nothrow @nogc @safe {
	x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9;
	x = (x ^ (x >> 27)) * 0x94d049bb133111eb;
	x = x ^ (x >> 31);
	return x;
}


struct HashMap(T, Value, alias hashFunc=defaultHashFunc){
	enum rehashFactor=0.75;
	enum size_t getIndexEmptyValue=size_t.max;

	static struct KeyVal{
		T key;
		Value value;
	}

	static struct Bucket{
		ulong hash;
		KeyVal keyValue;
	}

	
	Vector!Bucket elements;// Length should be always power of 2
	size_t length;// Used to compute loadFactor


	void clear(){
		elements.clear();
		length=0;
	}

	void reset(){
		elements.reset();
		length=0;
	}


	bool isIn(ref T el){
		return getIndex(el)!=getIndexEmptyValue;
	}

	bool isIn(T el){
		return getIndex(el)!=getIndexEmptyValue;
	}

	ref T get()(auto ref T k){
		size_t index=getIndex(k);
		assert(index!=getIndexEmptyValue);
		return elements[index].keyValue.value;
		
	}

	deprecated("Use get with second parameter.")
	auto ref T getDefault()(auto ref T k, auto ref Value defaultValue){
		return get(k, defaultValue);
	}

	auto ref T get()(auto ref T k, auto ref Value defaultValue){
		size_t index=getIndex(k);
		if(index==getIndexEmptyValue){
			return defaultValue;
		}else{
			return elements[index].keyValue.value;
		}		
	}
	
	ref T getInsertDefault()(auto ref T k, auto ref Value defaultValue){		
		size_t index=getIndex(k);
		if(index==getIndexEmptyValue){
			add(k, defaultValue);
		}
		index=getIndex(k);
		assert(index!=getIndexEmptyValue);
		return elements[index].keyValue.value;
		
	}
	
	bool tryRemove(T el) {
		size_t index=getIndex(el);
		if(index==getIndexEmptyValue){
			return false;
		}
		length--;
		elements[index].hash=HASH_DELETED;
		return true;
	}
	
	void remove(T el) {
		bool ok=tryRemove(el);
		assert(ok);
	}


	void add()(auto ref T el, auto ref Value value){
		if(isIn(el)){
			return;
		}
		
		if(getLoadFactor(length+1)>rehashFactor){
			rehash();
		}
		length++;
		
		immutable ulong hash=hashFunc(el) | HASH_FILLED_MARK;
		immutable size_t rotateMask=elements.length-1;
		ulong index=hash & rotateMask;// Starting point

		while(true){
			Bucket* gr=&elements[index];
			if( (gr.hash & HASH_FILLED_MARK) == 0 ){
				gr.hash=hash;
				gr.keyValue.key=el;
				gr.keyValue.value=value;
				return;
			}

			index++;
			index=index & rotateMask;
		}
	}

	// For debug
	//int numA;
	//int numB;

	size_t getIndex(T el) {
		return getIndex(el);
	}

	size_t getIndex(ref T el) {
		mixin(doNotInline);

		immutable size_t groupsLength=elements.length;
		if(groupsLength==0){
			return getIndexEmptyValue;
		}

		immutable ulong hash=hashFunc(el) | HASH_FILLED_MARK;
		immutable size_t rotateMask=groupsLength-1;
		size_t index=hash & rotateMask;// Starting point

		//numA++;
		while( true ){
			//numB++;
			Bucket* gr=&elements[index];
			if(gr.hash==hash && gr.keyValue.key==el ){
				return index;
			}
			if(gr.hash==HASH_EMPTY ){
				return getIndexEmptyValue;
			}

			index++;
			index=index & rotateMask;
		}
		
	}	


	float getLoadFactor(size_t forElementsNum) {
		if(elements.length==0){
			return 1;
		}
		return cast(float)forElementsNum/(elements.length);
	}

	void rehash() {
		mixin(doNotInline);
		// Get all elements
		Vector!KeyVal allElements;
		allElements.reserve(elements.length);
		
		foreach(ref Bucket el; elements){
			if( (el.hash & HASH_FILLED_MARK)==0 ){
				el.hash=HASH_EMPTY;
				continue;
			}
			el.hash=HASH_EMPTY;
			allElements~=el.keyValue;
			
		}
		
		if(getLoadFactor(length+1)>rehashFactor){// Reallocate
			elements.length=(elements.length?elements.length:2)<<1;// Power of two, initially 8 elements
		}
		
		// Insert elements
		foreach(i,ref el;allElements){
			add(el.key, el.value);
		}
		length=allElements.length;
	}


	// foreach support
	int opApply(DG)(scope DG  dg) { 
		int result;
		foreach(ref Bucket gr; elements){
			if( (gr.hash & HASH_FILLED_MARK)==0 ){
				continue;
			}
			static if(isForeachDelegateWithTypes!(DG, T) ){
				result=dg(gr.keyValue.key);
			}else static if( isForeachDelegateWithTypes!(DG, Value) ){
				result=dg(gr.keyValue.value);
			}else static if( isForeachDelegateWithTypes!(DG, T, Value) ){
				result=dg(gr.keyValue.key, gr.keyValue.value);
			}else{
				static assert(0);
			}
			if (result)
				break;	
			
		}		
		
		return result;
	}

	int byKey(scope int delegate(T k) dg){
		int result;
		foreach(ref T k; this){
			result=dg(k);
			if (result)
				break;	
		}
		return result;		
	}
	
	int byValue(scope int delegate(ref Value k) dg){
		int result;
		foreach(ref Value v; this){
			result=dg(v);
			if (result)
				break;	
		}
		return result;		
	}
	
	int byKeyValue(scope int delegate(ref T k, ref Value v) dg){
		int result;
		foreach(ref T k, ref Value v; this){
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

	// Make distripution plot
	void saveGroupDistributionPlot(string path){
		enum distributionsNum=1024*8;
		BenchmarkData!(1, distributionsNum) distr;// For now use benchamrk as a plotter
		
		foreach(ref T el; this){
			immutable size_t rotateMask=elements.length-1;
			ulong group=hashFunc(el) & rotateMask;
			if(group>=distributionsNum){
				continue;
			}
			distr.times[0][group]++;
			
		}
		distr.plotUsingGnuplot(path, ["group distribution"]);
	}
	
}




unittest{
	HashMap!(int, int) set;
	
	assert(set.isIn(123)==false);
	set.add(123, 1);
	set.add(123, 1);
	assert(set.isIn(123)==true);
	assert(set.isIn(122)==false);
	assert(set.length==1);
	set.remove(123);
	assert(set.isIn(123)==false);
	assert(set.length==0);
	assert(set.tryRemove(500)==false);
	set.add(123, 1);
	assert(set.tryRemove(123)==true);
	
	
	foreach(i;1..130){
		set.add(i, 1);		
	}

	foreach(i;1..130){
		assert(set.isIn(i));
	}

	foreach(i;130..500){
		assert(!set.isIn(i));
	}

	foreach(int el; set){
		assert(set.isIn(el));
	}
}

unittest{
	HashMap!(int, int) map;
	map.add(1, 10);
	assert(map.get(1)==10);
	assert(map.get(2, 20)==20);
	assert(!map.isIn(2));
	assert(map.getInsertDefault(2, 20)==20);
	assert(map.get(2)==20);
	foreach(k; &map.byKey){}
	foreach(k, v; &map.byKeyValue){}
	foreach(v; &map.byValue){}
	
}



void benchmarkHashMapInt(){
	HashMap!(int, int) set;
	byte[int] mapStandard;
	uint elementsNumToAdd=cast(uint)(65536*0.74);
	// Add elements
	foreach(int i;0..elementsNumToAdd){
		set.add(i, 1);
		mapStandard[i]=1;
	}
	// Check if isIn is working
	foreach(int i;0..elementsNumToAdd){
		assert(set.isIn(i));
		assert((i in mapStandard) !is null);
	}
	// Check if isIn is returning false properly
	foreach(int i;elementsNumToAdd..elementsNumToAdd+10_000){
		assert(!set.isIn(i));
		assert((i in mapStandard) is null);
	}
	//set.numA=set.numB=set.numC=0;
	enum itNum=100;
	BenchmarkData!(2, itNum) bench;
	doNotOptimize(set);// Make some confusion for compiler
	doNotOptimize(mapStandard);
	ushort myResults;
	myResults=0;
	//benchmark standard library implementation
	foreach(b;0..itNum){
		bench.start!(1)(b);
		foreach(i;0..elementsNumToAdd){
			auto ret=myResults in mapStandard;
			myResults+=1+cast(bool)ret;//cast(typeof(myResults))(cast(bool)ret);
			doNotOptimize(ret);
		}
		bench.end!(1)(b);
	}
	
	auto stResult=myResults;
	//benchmark this implementation
	myResults=0;
	foreach(b;0..itNum){
		bench.start!(0)(b);
		foreach(i;0..elementsNumToAdd){
			auto ret=set.isIn(myResults);
			myResults+=1+ret;//cast(typeof(myResults))(ret);
			doNotOptimize(ret);
		}
		bench.end!(0)(b);
	}
	assert(myResults==stResult);// Same behavior as standard map
	//writeln(set.getLoadFactor(set.length));
	//writeln(set.numA);
	//writeln(set.numB);
	
	doNotOptimize(myResults);
	bench.plotUsingGnuplot("testA.png",["my", "standard"]);
	set.saveGroupDistributionPlot("distrA.png");	
}


void benchmarkHashMapPerformancePerElement(){
	ushort trueResults;
	doNotOptimize(trueResults);
	enum itNum=100;
	BenchmarkData!(2, itNum) bench;
	HashMap!(int, int) set;
	byte[int] mapStandard;
	//writeln(set.getLoadFactor(set.length));
	//set.numA=set.numB=set.numC=0;
	size_t lastAdded;
	size_t numToAdd=16*8;

	foreach(b;0..itNum){
		foreach(i;lastAdded..lastAdded+numToAdd){
			mapStandard[cast(uint)i]=true;
		}
		lastAdded+=numToAdd;
		bench.start!(1)(b);
		foreach(i;0..1000_00){
			auto ret=trueResults in mapStandard;
			trueResults+=1;//cast(typeof(trueResults))(cast(bool)ret);
			doNotOptimize(ret);
		}
		bench.end!(1)(b);
	}
	lastAdded=0;
	trueResults=0;
	foreach(b;0..itNum){
		foreach(i;lastAdded..lastAdded+numToAdd){
			set.add(cast(uint)i, 1);
		}
		lastAdded+=numToAdd;
		bench.start!(0)(b);
		foreach(i;0..1000_00){
			auto ret=set.isIn(trueResults);
			trueResults+=1;//cast(typeof(trueResults))(ret);
			doNotOptimize(ret);
		}
		bench.end!(0)(b);
	}
	//writeln(set.numA);
	//writeln(set.numB);
	doNotOptimize(trueResults);
	bench.plotUsingGnuplot("test.png",["my", "standard"]);
	//set.saveGroupDistributionPlot("distr.png");

}
