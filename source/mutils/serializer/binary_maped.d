module mutils.serializer.binary_maped;

import std.meta;
import std.stdio;
import std.traits;

import mutils.container.vector;
public import mutils.serializer.common;
import mutils.type_info;

// THINK ABOUT: if serializer returns false con should: notbe changed, shoud be at the end of var, undefined??

struct TypeData {
	string nameFromBase;
	string name;
	long size;
	long aligment;
	Field[] fields;
	bool isBasicType;
	bool isMallocType;
	bool isStaticArray;
	bool isCustomVector;
	bool isCustomMap;
	bool isStringVector;
}

struct Field {
	string name;
	TypeData typeData;
}

TypeData getTypeData(T)(string nameFromBase = "") {
	TypeData data;
	data.name = T.stringof;
	data.size = T.sizeof;
	data.aligment = T.alignof;
	data.isBasicType = isBasicType!T;
	data.isStaticArray = isStaticArray!T;
	data.isCustomVector = isCustomVector!T;
	data.isCustomMap = isCustomMap!T;
	data.isStringVector = isStringVector!T;

	static if (is(T == struct) && !isCustomVector!T && !isCustomMap!T && !isStringVector!T) {
		alias TFields = Fields!T;
		alias Names = FieldNameTuple!T;
		foreach (i, F; TFields) {
			alias TP = AliasSeq!(__traits(getAttributes, T.tupleof[i]));
			bool noserialize = hasNoserializeUda!(TP) || isMallocType!T;
			if (!noserialize) {
				data.fields ~= Field(Names[i], getTypeData!F(nameFromBase ~ "." ~ Names[i]));
			}
		}
	}
	return data;
}

long alignPtrDt(long val, long aligment) {
	auto k = aligment - 1;
	return (val + k) & ~(k);
}

ubyte[] toBytes(T)(ref T val) {
	return (cast(ubyte*)&val)[0 .. T.sizeof];
}

enum VariableType : byte {
	char_,
	byte_,
	ubyte_,
	short_,
	ushort_,
	int_,
	uint_,
	long_,
	ulong_,
	float_,
	double_,
	real_,
	struct_,
	class_,
	stringVector,
	customVector,
	customMap,
	staticArray,
}

VariableType getSerVariableType(TTT)() {
	alias T = Unqual!TTT;

	static if (is(T == char)) {
		return VariableType.char_;
	} else static if (is(T == byte)) {
		return VariableType.byte_;
	} else static if (is(T == ubyte)) {
		return VariableType.ubyte_;
	} else static if (is(T == short)) {
		return VariableType.short_;
	} else static if (is(T == ushort)) {
		return VariableType.ushort_;
	} else static if (is(T == int)) {
		return VariableType.int_;
	} else static if (is(T == uint)) {
		return VariableType.uint_;
	} else static if (is(T == long)) {
		return VariableType.long_;
	} else static if (is(T == ulong)) {
		return VariableType.ulong_;
	} else static if (is(T == float)) {
		return VariableType.float_;
	} else static if (is(T == double)) {
		return VariableType.double_;
	} else static if (is(T == real)) {
		return VariableType.real_;
	} else static if (is(T == struct)) {
		return VariableType.struct_;
	} else static if (is(T == class)) {
		return VariableType.class_;
	} else static if (isStringVector!T) {
		return VariableType.stringVector;
	} else static if (isCustomVector!T) {
		return VariableType.customVector;
	} else static if (isCustomMap!T) {
		return VariableType.customMap;
	} else static if (isStaticArray!T) {
		return VariableType.staticArray;
	} else static if (isCustomMap!T) {
		return VariableType.customMap;
	} else {
		static assert(0, "Type not supported 2307");
	}
}

bool isSerBasicType(VariableType type) {
	return (type >= VariableType.char_ && type <= VariableType.real_);
}

SizeType getSerVariableTypeSize(VariableType type) {
	switch (type) {
	case VariableType.char_:
	case VariableType.byte_:
	case VariableType.ubyte_:
		return 1;
	case VariableType.short_:
	case VariableType.ushort_:
		return 2;
	case VariableType.int_:
	case VariableType.uint_:
	case VariableType.float_:
		return 4;
	case VariableType.long_:
	case VariableType.ulong_:
	case VariableType.double_:
		return 8;
	case VariableType.real_:
		static assert(real.sizeof == 16);
		static assert(real.alignof == 16);
		return 16;
	default:
		return 0;
	}
}

void serializeType(Load load, ContainerOrSlice)(ref VariableType type, ref ContainerOrSlice con) {
	if (load == Load.yes) {
		type = cast(VariableType) con[0];
		con = con[1 .. $];
	} else {
		con ~= cast(ubyte) type;
	}
	//writeln(size);
}

struct SerBasicVariable {
	align(16) ubyte[16] data; // Strictest aligment and biggest size of basic types

	VariableType type;
	bool serialize(Load load, ContainerOrSlice)(ref ContainerOrSlice con) {
		serializeType!(load)(type, con);

		if (!isSerBasicType(type)) {
			return false;
		}

		SizeType varSize = getSerVariableTypeSize(type);

		static if (load == Load.yes) {
			data[0 .. varSize] = con[0 .. varSize];
			con = con[varSize .. $];
		} else {
			con ~= data[0 .. varSize];
		}
		return true;
	}

	T get(T)() {
		enum VariableType typeT = getSerVariableType!T;
		enum SizeType varSize = getSerVariableTypeSize(typeT);
		assert(typeT == type);
		assert(T.sizeof == varSize);
		T var;
		toBytes(var)[0 .. T.sizeof] = data[0 .. T.sizeof];
		return var;
	}

	real getReal() {
		switch (type) {
		case VariableType.char_:
			return get!char;
		case VariableType.byte_:
			return get!byte;
		case VariableType.ubyte_:
			return get!ubyte;
		case VariableType.short_:
			return get!short;
		case VariableType.ushort_:
			return get!ushort;
		case VariableType.int_:
			return get!int;
		case VariableType.uint_:
			return get!uint;
		case VariableType.float_:
			return get!float;
		case VariableType.long_:
			return get!long;
		case VariableType.ulong_:
			return get!ulong;
		case VariableType.double_:
			return get!double;
		case VariableType.real_:
			return get!real;
		default:
			break;
		}

		return 0;
	}

	real getLong() {
		switch (type) {
		case VariableType.char_:
			return get!char;
		case VariableType.byte_:
			return get!byte;
		case VariableType.ubyte_:
			return get!ubyte;
		case VariableType.short_:
			return get!short;
		case VariableType.ushort_:
			return get!ushort;
		case VariableType.int_:
			return get!int;
		case VariableType.uint_:
			return get!uint;
		case VariableType.float_:
			return get!float;
		case VariableType.long_:
			return get!long;
		case VariableType.ulong_:
			return get!ulong;
		case VariableType.double_:
			return get!double;
		case VariableType.real_:
			return get!real;
		default:
			break;
		}

		return 0;
	}
}

alias SizeNameType = ubyte;
alias SizeType = uint;

struct BinarySerializerMaped {
	__gshared static BinarySerializerMaped instance;

	static ubyte[] beginObject(Load load, ContainerOrSlice)(ref ContainerOrSlice con) {
		ubyte[] orginalSlice = con[];

		SizeType objectSize = 0; // 0 is a placeholder value during save, proper value will be assigned in endObject
		serializeSize!(load)(objectSize, con);

		static if (load == Load.yes) {
			con = con[0 .. objectSize];
			ubyte[] afterObjectSlice = orginalSlice[SizeType.sizeof + objectSize .. $];
			return afterObjectSlice;
		} else {
			return orginalSlice;
		}

	}

	static void endObject(Load load, ContainerOrSlice)(ref ContainerOrSlice con, ubyte[] slice) {
		static if (load == Load.yes) {
			con = slice;
		} else {
			SizeType objectSize = cast(SizeType)(con.length - (slice.length + SizeType.sizeof));
			con[slice.length .. slice.length + SizeType.sizeof] = toBytes(objectSize); // override object size
		}

	}

	static bool serializeWithName(Load load, string name, TypeData typeData, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		static if (load == Load.yes) {
			return serializeByName!(load, name, typeData)(var, con);
		} else {
			serializeName!(load)(name, con);
			serialize!(load, typeData)(var, con);
			return true;
		}

	}

	static bool serialize(Load load, TypeData typeData, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		static if (hasMember!(T, "customSerialize")) {
			var.customSerialize!(load)(ser, con);
			return true;
		} else static if (typeData.isBasicType) {
			return serializeBasicVar!(load)(var, con);
		} else static if (typeData.isCustomVector) {
			return serializeCustomVector!(load)(var, con);
		} else static if (typeData.isStaticArray) {
			return serializeStaticArray!(load)(var, con);
		} else static if (typeData.isCustomMap) {
			return serializeCustomMap!(load)(var, con);
		} else static if (is(T == struct)) {
			return serializeStruct!(load, typeData)(var, con);
		} else {
			static assert(0, "Not supported");
		}
	}

	//////////////////////// IMPL

	static bool serializeBasicVar(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(isBasicType!T);

		enum VariableType properType = getSerVariableType!T;
		VariableType type = properType;

		static if (load == Load.yes) {
			serializeTypeNoPop!(load)(type, con);
			if (type != properType) {
				return serializeBasicVarWithConversion!(load)(var, con);
			}
		}

		serializeType!(load)(type, con);
		static if (load == Load.yes) {
			toBytes(var)[0 .. T.sizeof] = con[0 .. T.sizeof];
			con = con[T.sizeof .. $];
		} else {
			con ~= toBytes(var);
		}
		return true;
	}

	static bool serializeBasicVarWithConversion(Load load, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		static assert(load == Load.yes);

		enum VariableType properType = getSerVariableType!T;

		VariableType type;
		serializeTypeNoPop!(load)(type, con);

		if (!isSerBasicType(type)) {
			return false;
		}

		SerBasicVariable serBasicVar;
		serBasicVar.serialize!(load)(con);

		static if (isFloatingPoint!T) {
			var = cast(T) serBasicVar.getReal();
		} else static if (isIntegral!T || is(T == char)) {
			var = cast(T) serBasicVar.getLong();
		}

		return true;
	}

	static bool serializeStruct(Load load, TypeData typeData, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		static assert(is(T == struct));

		enum VariableType properType = getSerVariableType!T;
		VariableType type = properType;
		serializeType!(load)(type, con);
		if (type != VariableType.struct_) {
			return false;
		}

		ubyte[] begin = beginObject!(load)(con);
		scope (exit)
			endObject!(load)(con, begin);

		alias nums = AliasSeq!(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12);
		foreach (i; nums[0 .. typeData.fields.length]) {
			enum Field field = typeData.fields[i];
			string varName = field.name;
			static if (load == Load.yes) {
				serializeByName!(load, field.name, field.typeData)(__traits(getMember,
						var, field.name), con);
			} else {
				serializeName!(load)(varName, con);
				serialize!(load, field.typeData)(__traits(getMember, var, field.name), con);
			}
		}

		return true;
	}

	static bool serializeSlice(Load load, T, ContainerOrSlice)(T[] var, ref ContainerOrSlice con) {
		assert(var.length < SizeType.max);

		ubyte[] begin = beginObject!(load)(con);
		scope (exit)
			endObject!(load)(con, begin);

		SizeType elemntsNum = cast(SizeType) var.length;
		serializeSize!(load)(elemntsNum, con);
		import std.algorithm : min;

		size_t elementsToLoadSave = min(var.length, elemntsNum);

		static if (load == Load.yes) {
			VariableType type;
			serializeTypeNoPop!(load)(type, con);
			SizeType oneElementSize = getSerVariableTypeSize(type);
			auto conSliceStart = con;
		}

		foreach (i; 0 .. elementsToLoadSave) {
			bool ok = serialize!(load, getTypeData!(T))(var[i], con);
			if (!ok) {
				return false;
			}
		}

		static if (load == Load.yes) {
			con = conSliceStart[oneElementSize * elementsToLoadSave .. $];
		}
		return true;
	}

	static bool serializeStaticArray(Load load, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		static assert(isStaticArray!T);

		VariableType type = VariableType.staticArray;
		serializeType!(load)(type, con);
		if (type != VariableType.staticArray && type != VariableType.customVector) {
			return false;
		}
		return serializeSlice!(load)(var[], con);
	}

	static bool serializeCustomVector(Load load, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		alias ElementType = Unqual!(ForeachType!(T));

		VariableType type = VariableType.customVector;
		serializeType!(load)(type, con);
		if (type != VariableType.customVector && type != VariableType.staticArray) {
			return false;
		}

		static if (load == Load.yes) {
			static if (hasMember!(T, "initialize")) {
				var.initialize();
			}
			auto sliceTmp = con;
			SizeType elementsNum;
			serializeSize!(load)(elementsNum, sliceTmp); // Size of whole slice data - ignore
			serializeSize!(load)(elementsNum, sliceTmp);
			var.length = elementsNum;
		}

		return serializeSlice!(load)(var[], con);
	}

	static bool serializeCustomMap(Load load, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		static assert(isCustomMap!T);

		VariableType type = VariableType.customMap;
		serializeType!(load)(type, con);
		if (type != VariableType.customMap) {
			return false;
		}
		//uint dataLength = cast(uint)(var.length);
		//serialize!(loadOrSkip!load)(dataLength, con);

		ubyte[] begin = beginObject!(load)(con);
		scope (exit)
			endObject!(load)(con, begin);

		SizeType elemntsNum = cast(SizeType) var.length;
		serializeSize!(load)(elemntsNum, con);

		static if (load == Load.yes) {
			static if (hasMember!(T, "initialize")) {
				var.initialize();
			}
			static if (hasMember!(T, "reserve")) {
				var.reserve(elemntsNum);
			}
			foreach (i; 0 .. elemntsNum) {
				bool ok;
				T.Key key;
				T.Value value;
				ok = serialize!(load, getTypeData!(T.Key))(key, con);
				if (!ok) {
					return false;
				}
				ok = serialize!(load, getTypeData!(T.Value))(value, con);
				if (!ok) {
					return false;
				}
				var.add(key, value);
			}
		} else {
			foreach (ref key, ref value; &var.byKeyValue) {
				serialize!(load, getTypeData!(T.Key))(key, con);
				serialize!(load, getTypeData!(T.Value))(value, con);
			}
		}
		return false;
	}

	//////////////////////////////////////////////// HELPERS

	static bool serializeByName(Load load, string name, TypeData typeData, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		static assert(load == Load.yes);
		auto conBegin = con;
		scope (exit)
			con = conBegin; // Revert slice

		foreach (noInfiniteLoop; 0 .. 1000) {
			string varName;
			serializeName!(load)(varName, con);

			if (varName is null) {
				break;
			}

			ubyte[] conStartVar = con;

			VariableType type;
			serializeType!(load)(type, con);

			SizeType varSize;
			SizeType sizeSize;

			if (isSerBasicType(type)) {
				varSize = getSerVariableTypeSize(type);
			} else {
				serializeSize!(load)(varSize, con);
				sizeSize = SizeType.sizeof;
			}
			SizeType varEnd = 1 + sizeSize + varSize;

			if (varName == name) {
				ubyte[] conStartVarTmp = conStartVar[0 .. varEnd];
				bool loaded = serialize!(load, typeData)(var, conStartVarTmp);
				if (loaded) {
					if (noInfiniteLoop == 0) { // Move con because no one will read this value again(no key duplicates)
						conBegin = conStartVar[varEnd .. $];
					}
					return true;
				}
			}
			if (varEnd >= conStartVar.length) {
				return false;
			}
			con = conStartVar[varEnd .. $];
		}
		return false;
	}

	private static void serializeName(Load load, ContainerOrSlice)(auto ref string name,
			ref ContainerOrSlice con) {
		if (load == Load.yes) {
			if (con.length < SizeNameType.sizeof) {
				name = null;
				return;
			}
			SizeNameType nameLength;
			toBytes(nameLength)[0 .. SizeNameType.sizeof] = con[0 .. SizeNameType.sizeof];
			con = con[SizeNameType.sizeof .. $];
			name = cast(string) con[0 .. nameLength];
			con = con[nameLength .. $];
		} else {
			assert(name.length <= SizeNameType.max);
			SizeNameType nameLength = cast(SizeNameType) name.length;
			con ~= toBytes(nameLength);
			con ~= cast(ubyte[]) name;
		}
		//writeln(name.length);
	}

	private static void serializeTypeNoPop(Load load, ContainerOrSlice)(
			ref VariableType type, ref ContainerOrSlice con) {
		static assert(load == Load.yes);

		type = cast(VariableType) con[0];

	}

	private static void serializeSize(Load load, ContainerOrSlice)(ref SizeType size,
			ref ContainerOrSlice con) {
		if (load == Load.yes) {
			toBytes(size)[0 .. SizeType.sizeof] = con[0 .. SizeType.sizeof];
			con = con[SizeType.sizeof .. $];
		} else {
			con ~= toBytes(size);
		}
	}

	private static void serializeSizeNoPop(Load load, ContainerOrSlice)(ref SizeType size,
			ref ContainerOrSlice con) {
		static assert(load == Load.yes);

		toBytes(size)[0 .. SizeType.sizeof] = con[0 .. SizeType.sizeof];
	}

}

// test basic type
unittest {
	int test = 1;

	Vector!ubyte container;
	//save
	BinarySerializerMaped.serializeWithName!(Load.no, "name",
			getTypeData!(typeof(test)))(test, container);
	assert(container.length == SizeNameType.sizeof + 4 + VariableType.sizeof + 4);

	//reset var
	test = 0;
	//load
	ubyte[] dataSlice = container[];
	BinarySerializerMaped.serializeWithName!(Load.yes, "name",
			getTypeData!(typeof(test)))(test, dataSlice);
	assert(test == 1);
	//assert(dataSlice.length==0);
}

unittest {
	static struct Test {
		int a;
		long b;
		ubyte c;
	}

	static struct TestB {
		int bbbb;
		long c;
		char a;
	}

	Test test = Test(1, 2, 3);
	Vector!ubyte container;
	//save
	BinarySerializerMaped.serializeWithName!(Load.no, "name",
			getTypeData!(typeof(test)))(test, container);
	assert(container.length == SizeNameType.sizeof + 4 + VariableType.sizeof
			+ SizeType.sizeof + 3 * SizeNameType.sizeof + 3 + 3 * VariableType.sizeof + 4 + 8 + 1);
	//writeln("Ratio to ideal minimal size: ", container.length/(4.0f+8.0f+1.0f));
	//reset var
	TestB testB;

	//load
	ubyte[] dataSlice = container[];
	BinarySerializerMaped.serializeWithName!(Load.yes, "name",
			getTypeData!(typeof(testB)))(testB, dataSlice);
	assert(testB == TestB(0, 3, 1));
}
// empty struct
unittest {
	static struct Test {
	}

	static struct TestB {
		int aa;
		int bb;
	}

	Test test = Test();
	Vector!ubyte container;
	//save
	BinarySerializerMaped.serializeWithName!(Load.no, "name",
			getTypeData!(typeof(test)))(test, container);
	//reset var
	TestB testB;
	//load
	ubyte[] dataSlice = container[];
	BinarySerializerMaped.serializeWithName!(Load.yes, "name",
			getTypeData!(typeof(testB)))(testB, dataSlice);

}

// vectors
unittest {
	static struct Test {
		int[4] aa;
		Vector!ubyte bb;
		int[3] cc;
	}

	static struct TestB {
		Vector!long bb;
		int[2] aa;
		Vector!int cc;
	}

	enum ubyte[] bytesA = [3, 2, 1];
	enum long[] bytesB = [3, 2, 1];
	Test test = Test([1, 2, 3, 4], Vector!ubyte(bytesA), [10, 20, 30]);
	Vector!ubyte container;
	//save
	BinarySerializerMaped.serializeWithName!(Load.no, "name",
			getTypeData!(typeof(test)))(test, container);

	//reset var
	TestB testB;
	//load
	ubyte[] dataSlice = container[];
	BinarySerializerMaped.serializeWithName!(Load.yes, "name",
			getTypeData!(typeof(testB)))(testB, dataSlice);

	assert(testB == TestB(Vector!long(bytesB), [1, 2], Vector!int([10, 20, 30])));
}

// test custom map
unittest {
	import mutils.container.hash_map;

	static struct TestStruct {
		int a;
		int b;
	}

	static struct TestStructB {
		ushort b;
		long a;
		char c;
	}

	HashMap!(int, TestStruct) map;
	map.add(1, TestStruct(1, 11));
	map.add(7, TestStruct(7, 77));

	Vector!ubyte container;

	//save
	BinarySerializerMaped.serializeWithName!(Load.no, "name",
			getTypeData!(typeof(map)))(map, container);

	//reset var
	HashMap!(byte, TestStructB) mapB;
	//load
	ubyte[] dataSlice = container[];
	BinarySerializerMaped.serializeWithName!(Load.yes, "name",
			getTypeData!(typeof(mapB)))(mapB, dataSlice);
	assert(mapB.get(1) == TestStructB(11, 1));
	assert(mapB.get(7) == TestStructB(77, 7));
}
