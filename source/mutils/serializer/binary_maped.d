module mutils.serializer.binary_maped;


import mutils.type_info;

import std.meta;
import std.stdio;
import std.traits;

public import mutils.serializer.common;



struct TypeData{
	string nameFromBase;
	string name;
	long size;
	long aligment;
	Field[] fields;
	bool isBasicType;
	bool isMallocType;
	bool isCustomVector;
	bool isCustomMap;
	bool isStringVector;
}



struct Field{
	string name;
	TypeData typeData;
}



TypeData getTypeData(T)(string nameFromBase=""){
	TypeData data;
	data.name=T.stringof;
	data.size=T.sizeof;
	data.aligment=T.alignof;
	data.isBasicType=isBasicType!T;
	data.isCustomVector=isCustomVector!T;
	data.isCustomVector=isCustomMap!T;
	data.isStringVector=isStringVector!T;
	
	static if( is(T==struct) && !isCustomVector!T && !isCustomMap!T && !isStringVector!T){
		alias TFields=Fields!T;
		alias Names=FieldNameTuple!T;
		foreach(i, F; TFields){
			alias TP = AliasSeq!(__traits(getAttributes, T.tupleof[i]));
			bool noserialize=hasNoserializeUda!(TP) || isMallocType!T;
			if(!noserialize){
				data.fields~=Field(Names[i], getTypeData!F(nameFromBase~"."~Names[i]));
			}
		}
	}
	return data;
}


long alignPtrDt(long val, long aligment){
	auto k=aligment-1;
	return (val + k) & ~( k);
}

ubyte[] toBytes(T)(ref T val){
	return  (cast(ubyte*)&val) [0..T.sizeof];
}

alias SizeNameType=ubyte;
alias SizeType=uint;

struct BinarySerializerMaped{
	__gshared static BinarySerializerMaped instance;


	static ubyte[] beginObject(Load load, ContainerOrSlice)(ref ContainerOrSlice con){
		ubyte[] orginalSlice=con[];

		SizeType objectSize=0;// 0 is a placeholder value during save, proper value will be assigned in endObject
		serializeSize!(load)(objectSize, con);

		static if(load==Load.yes){
			con=con[0..objectSize];
			ubyte[] afterObjectSlice=con[objectSize..$];
			return afterObjectSlice;
		}else{
			return orginalSlice;
		}

	}
	
	static void endObject(Load load, ContainerOrSlice)(ref ContainerOrSlice con, ubyte[] slice){
		static if(load==Load.yes){
			con=slice;
		}else{
			SizeType objectSize=cast(SizeType)( con.length-(slice.length+SizeType.sizeof) );
			con[slice.length..slice.length+SizeType.sizeof]=toBytes(objectSize); // override object size
		}

	}

	private static void serializeName(Load load, ContainerOrSlice)(auto ref string name, ref ContainerOrSlice con){
		if(load==Load.yes){
			SizeNameType nameLength;
			toBytes(nameLength)[0..SizeNameType.sizeof]=con[0..SizeNameType.sizeof];
			con=con[SizeNameType.sizeof..$];
			name=cast(string)con[0..nameLength];
			con=con[nameLength..$];
		}else{
			assert(name.length<=SizeNameType.max);
			SizeNameType nameLength=cast(SizeNameType)name.length;
			con~=toBytes(nameLength);
			con~=cast(ubyte[])name;		
		}
		//writeln(name.length);
	}

	private static void serializeSize(Load load, ContainerOrSlice)(ref SizeType size, ref ContainerOrSlice con){
		if(load==Load.yes){
			toBytes(size)[0..SizeType.sizeof]=con[0..SizeType.sizeof];
			con=con[SizeType.sizeof..$];
		}else{
			con~=toBytes(size);
		}
		//writeln(size);
	}

	private static void serializeSizeNoPop(Load load, ContainerOrSlice)(ref SizeType size, ref ContainerOrSlice con){
		if(load==Load.yes){
			toBytes(size)[0..SizeType.sizeof]=con[0..SizeType.sizeof];
		}else{
			con~=toBytes(size);
		}
	}


	static bool serializeByName(Load load, string name, TypeData typeData, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con){
		auto conBegin=con;
		scope(exit)con=conBegin;// Revert slice
		
		foreach(noInfiniteLoop; 0..1000){
			string varName;
			serializeName!(load)(varName, con);
			
			SizeType varSize;
			serializeSizeNoPop!(load)(varSize, con);
			ubyte[] conStartVar=con[SizeType.sizeof..$];
			
			if(varName.length==name.length && varName==name){
				bool loaded=serialize!(load, typeData)(var, con);
				if(loaded){
					if(noInfiniteLoop==0){// Move con because no one will read this value again(no key duplicates)
						conBegin=conStartVar[varSize..$];
					}
					return true;
				}
			}
			if(varSize>=conStartVar.length){
				return false;
			}
			con=conStartVar[varSize..$];
		}
		return false;
	}

	static bool serializeWithName(Load load, string name, TypeData typeData, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con){
		static if(load==Load.yes){
			return serializeByName!(load, name, typeData)(var, con);			
		}else{
			serializeName!(load)(name, con);	
			serialize!(load, typeData)(var, con);
			return true;
		}

	
	}

	static bool serialize(Load load, TypeData typeData, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con){
		static if (hasMember!(T, "customSerialize" )) {
			var.customSerialize!(load)(ser, con);
			return true;
		} else static if (typeData.isBasicType) {
			return serializeBasicVar!(load)(var, con);
		}else static if(typeData.isCustomVector){
			return serializeCustomVector!(load, typeData)(var, con);
		}else static if(typeData.isCustomMap){
			static assert(0, "Not implemented1");
		}else static if( is(T==struct) ){
			return serializeStruct!(load, typeData)(var, con);
		}else{
			static assert(0, "Not supported");
		}
	}

	static bool serializeBasicVar(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con){
		static assert(isBasicType!T);

		SizeType varSize=T.sizeof;
		serializeSize!(load)(varSize, con);
		assert(varSize==T.sizeof);

		static if(load==Load.yes){
			toBytes(var)[0..T.sizeof]=con[0..T.sizeof];
			con=con[T.sizeof..$];
		}else{
			con~=toBytes(var);
		}
		return true;
	}


	static bool serializeStruct(Load load, TypeData typeData, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con){
		static assert(is(T == struct));

		ubyte[] begin= beginObject!(load)(con);
		scope(exit)endObject!(load)(con, begin);

		alias nums=AliasSeq!(0, 1, 2, 3 , 4, 5, 6, 7, 8, 9, 10, 11, 12);		
		foreach(i; nums[0..typeData.fields.length]){
			enum Field field=typeData.fields[i];
			string varName=field.name;
			static if(load==Load.yes){
				serializeByName!(load, field.name, field.typeData)(__traits(getMember, var, field.name), con);	
			}else{
				serializeName!(load)(varName, con);	
				serialize!(load, field.typeData)(__traits(getMember, var, field.name), con);
			}
		}

		return true;
	}

	
	
}



import mutils.container.vector;
// test basic type
unittest{
	int test=1;
	
	Vector!ubyte container;	
	//save
	BinarySerializerMaped.serializeWithName!(Load.no, "name", getTypeData!(typeof(test)) )(test, container);
	assert(container.length==SizeNameType.sizeof+4+SizeType.sizeof+4);
	
	//reset var
	test=0;
	
	//load
	ubyte[] dataSlice=container[];
	BinarySerializerMaped.serializeWithName!(Load.yes, "name", getTypeData!(typeof(test)) )(test, dataSlice);
	assert(test==1);
	//assert(dataSlice.length==0);
}

// test basic types + endianness
unittest{
	//writeln("-");
	static struct Test{
		int a;
		long b;
		ubyte c;
	}

	static struct TestB{
		long bbbb;
		ubyte c;
		int a;
	}

	Test test=Test(1, 2, 3);
	Vector!ubyte container;	
	//save
	BinarySerializerMaped.serializeWithName!(Load.no, "name", getTypeData!(typeof(test)) )(test, container);
	//writeln(container[]);
	//writeln(cast(float)container.length/(4+8+1));
	assert(container.length==SizeNameType.sizeof+4  +SizeType.sizeof   +3*SizeNameType.sizeof+3  +3*SizeType.sizeof  +4+8+1);
	
	//reset var
	TestB testB;
	
	//load
	ubyte[] dataSlice=container[];
	BinarySerializerMaped.serializeWithName!(Load.yes, "name", getTypeData!(typeof(testB)) )(testB, dataSlice);
	//writeln(testB);
	assert(testB==TestB(0, 3, 1));
	//assert(dataSlice.length==0);
}