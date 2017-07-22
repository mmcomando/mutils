module mutils.container.ct_map;


import std.traits;
import std.meta;

import mutils.meta;






struct CTMap(ElementsPar...){
	static assert(ElementsPar.length%2==0);
	alias Elements=ElementsPar;

	struct KeyValue(alias KeyPar, alias ValPar){
		alias key=KeyPar; 
		alias value=ValPar; 
	}
	struct KeyValue(alias KeyPar, ValPar){
		alias key=KeyPar; 
		alias value=ValPar; 
	}
	struct KeyValue(KeyPar, alias ValPar){
		alias key=KeyPar; 
		alias value=ValPar; 
	}

	template getValues(){
		alias getValues=removeEven!Elements;
	}

	template getKeys(){
		alias getKeys=removeOdd!Elements;
	}
	
	template getValueType(){
		static assert(valuesHaveSameType);
		alias getValueType=typeof(Elements[1]);
	}
	
	template getKeyType(){
		static assert(keysHaveSameType);
		alias getKeyType=typeof(Elements[0]);
	}

	
	static bool valuesAreValueType(){
		return allSatisfy!(isExpressions, getValues!());
	}

	static bool keysAreValueType(){
		return allSatisfy!(isExpressions, getKeys!());
	}

	static bool valuesHaveSameType(){
		static if(keysAreValueType){
			alias Types=staticMap!(getType, getValues!());
			return NoDuplicates!(Types).length==1;
		}else{
			return false;
		}
	}

	static bool keysHaveSameType(){
		static if(keysAreValueType){
			alias Types=staticMap!(getType, getKeys!());
			return NoDuplicates!(Types).length==1;
		}else{
			return false;
		}
	}

	
	template getImpl(){
		auto getImpl(){
			foreach(i,Key;Elements){
				static if(i%2==0 &&
					(
						(__traits(compiles,T==Key) && T==Key) || 
						(__traits(compiles,is(T==Key)) && is(T==Key))
						)
					
					){//even elements are keys
					struct Returner{
						static if(isExpressions!(Elements[i+1])){
							enum value=Elements[i+1];
						}else{
							alias value=Elements[i+1];
						}
					}
					Returner ret;
					return ret;
				}
				
			}
		}
		
	}
	
	static auto get(T)(){
		mixin getImpl;
		return getImpl();
	}
	
	static auto get(alias T)(){
		mixin getImpl;
		return getImpl();
	}

	//static if(valuesHaveSameType && keysHaveSameType){
		alias byKeyValue=toKeyValue!(Elements);
	//}
	
	private template toKeyValue(Arr...){
		static if(Arr.length>2){
			alias toKeyValue=AliasSeq!(KeyValue!(Arr[0], Arr[1]), toKeyValue!(Arr[2..$]));
		}else static if(Arr.length==2){
			alias toKeyValue=AliasSeq!(KeyValue!(Arr[0], Arr[1]));
		}else{
			alias toKeyValue=AliasSeq!();
		}
	}

	
}


unittest{
	alias myMap=CTMap!(
		6,int,
		long, 12,
		18,23		
		);

	static assert(is(myMap.get!(6).value==int));
	static assert(myMap.get!(long).value==12);
	static assert(myMap.get!(18).value==23);
	static assert(!myMap.keysAreValueType);
	static assert(!myMap.valuesAreValueType);
}

unittest{
	alias myMap=CTMap!(
		"str1",8,
		"str2", 12,
		"str3",23		
		);

	static assert(myMap.keysAreValueType);
	static assert(myMap.valuesAreValueType);
	static assert(myMap.keysHaveSameType);
	static assert(myMap.valuesHaveSameType);
	static assert(is(myMap.getValueType!()==int));
	static assert(is(myMap.getKeyType!()==string));

}



unittest{
	alias myMap=CTMap!(
		"str1",8,
		"str2", 12,
		"str3",23		
		);

	
	int runtimeLookUp(string var){
		switch(var){
			foreach(keyValue;myMap.byKeyValue){
				case keyValue.key:
				return keyValue.value;
			}
			default:
				return 0;
		}
	}
	assert(runtimeLookUp("str0")==0);
	assert(runtimeLookUp("str1")==8);
	assert(runtimeLookUp("str2")==12);
	assert(runtimeLookUp("str3")==23);
	assert(runtimeLookUp("str4")==0);
}