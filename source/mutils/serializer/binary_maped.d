module mutils.serializer.binary_maped;

import std.algorithm : min;
import std.meta;
import std.stdio;
import std.traits;

import mutils.container.vector;
import mutils.conv;
public import mutils.serializer.common;

// THINK ABOUT: if serializer returns false con should: notbe changed, shoud be at the end of var, undefined??

ubyte[] toBytes(T)(ref T val) {
	return (cast(ubyte*)&val)[0 .. T.sizeof];
}

enum VariableType : byte {
	bool_,
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
	customMap,
	array,
	enum_,
}

VariableType getSerVariableType(TTT)() {
	alias T = Unqual!TTT;

	static if (is(T == bool)) {
		return VariableType.bool_;
	} else static if (is(T == char)) {
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
	} else static if (isCustomMap!T) {
		return VariableType.customMap;
	} else static if (isStaticArray!T) {
		return VariableType.staticArray;
	} else static if (isCustomMap!T) {
		return VariableType.customMap;
	} else static if (is(T == enum)) {
		return VariableType.enum_;
	} else {
		static assert(0, "Type not supported 2307");
	}
}

bool isSerBasicType(VariableType type) {
	return (type >= VariableType.bool_ && type <= VariableType.real_);
}

SizeType getSerVariableTypeSize(VariableType type) {
	switch (type) {
	case VariableType.bool_:
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
		case VariableType.bool_:
			return get!bool;
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
		assert(0); // TODO Log
		//return 0;
	}

	real getLong() {
		switch (type) {
		case VariableType.bool_:
			return get!bool;
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

		assert(0); // TODO Log
		//return 0;
	}
}

alias SizeNameType = ubyte;
alias SizeType = uint;

struct BinarySerializerMaped {
	alias SliceElementType = ubyte;
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

	//support for rvalues during load
	void serializeWithName(Load load, string name, T, ContainerOrSlice)(ref T var,
			ContainerOrSlice con) {
		static assert(load == Load.yes);
		serializeWithName!(load, name)(var, con);
	}

	static bool serializeWithName(Load load, string name, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		static if (load == Load.yes) {
			return serializeByName!(load, name)(var, con);
		} else {
			serializeName!(load)(name, con);
			serialize!(load)(var, con);
			return true;
		}

	}
	//support for rvalues during load
	void serialize(Load load, T, ContainerOrSlice)(ref T var, ContainerOrSlice con) {
		static assert(load == Load.yes);
		serialize!(load)(var, con);
	}

	static bool serialize(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static if (hasMember!(T, "customSerialize")) {
			var.customSerialize!(load)(instance, con);
			return true;
		} else static if (is(T == enum)) {
			return serializeEnum!(load)(var, con);
		} else static if (isBasicType!T) {
			return serializeBasicVar!(load)(var, con);
		} else static if (isStringVector!T) {
			return serializeStringVector!(load)(var, con);
		} else static if (isCustomVector!T) {
			return serializeCustomVector!(load)(var, con);
		} else static if (isStaticArray!T) {
			return serializeStaticArray!(load)(var, con);
		} else static if (isCustomMap!T) {
			return serializeCustomMap!(load)(var, con);
		} else static if (is(T == struct)) {
			return serializeStruct!(load)(var, con);
		} else static if (isPointer!T) {
			static assert(0, "Can not serialzie pointer");
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

	static bool serializeEnum(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static if (load == Load.yes) {
			SizeType varSize;
			serializeSize!(load)(varSize, con);
			string str = cast(string) con[0 .. varSize];
			var = str2enum(str);
			assert(str.length == 0);
		} else {
			char[256] buffer;
			string enumStr = enum2str(var, buffer);
			SizeType varSize = cast(SizeType) enumStr.length;
			serializeSize!(load)(varSize, con);
			con ~= cast(ubyte[])enumStr;
		}
		return true; //TODO return false when wrong enum is loaded
	}

	static bool serializeStruct(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
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

		foreach (i, ref a; var.tupleof) {
			alias TP = AliasSeq!(__traits(getAttributes, var.tupleof[i]));
			enum bool doSerialize = !hasNoserializeUda!(TP);
			static if (doSerialize) {
				enum string varName = __traits(identifier, var.tupleof[i]);
				static if (load == Load.yes) {
					serializeByName!(load, varName)(a, con);
				} else {
					serializeName!(load)(varName, con);
					serialize!(load)(a, con);
				}
			}
		}

		return true;
	}

	static bool serializeArray(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		assert(var.length < SizeType.max);

		ubyte[] begin = beginObject!(load)(con);
		scope (exit)
			endObject!(load)(con, begin);

		static if (load == Load.yes) {
			SizeType elemntsNum;
			serializeSize!(load)(elemntsNum, con);

			VariableType elementType;
			serializeTypeNoPop!(load)(elementType, con);
			auto conSliceStart = con;

			alias ElementType = Unqual!(ForeachType!(T));
			foreach (kkkkk; 0 .. elemntsNum) {
				ElementType el;
				bool ok = serialize!(load)(el, con);
				if (!ok) {
					return false;
				}
				var ~= el;
			}

			SizeType oneElementSize = getSerVariableTypeSize(elementType);
			con = conSliceStart[oneElementSize * elemntsNum .. $];
		} else {
			SizeType elemntsNum = 0;
			size_t conLengthSizeStart = con.length;
			serializeSize!(load)(elemntsNum, con); // Place holder, proper elementsNum will be saved later

			foreach (ref el; var) {
				bool ok = serialize!(load)(el, con);
				assert(ok);
				elemntsNum++;
			}
			SizeType* elementsNumPtr = cast(SizeType*)(con[].ptr + conLengthSizeStart);
			*elementsNumPtr = elemntsNum;

		}

		return true;
	}

	static bool serializeStaticArray(Load load, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		static assert(isStaticArray!T);

		VariableType type = VariableType.array;
		serializeType!(load)(type, con);
		if (type != VariableType.array) {
			return false;
		}
		ubyte[] begin = beginObject!(load)(con);
		scope (exit)
			endObject!(load)(con, begin);

		SizeType elemntsNum = cast(SizeType) var.length;
		serializeSize!(load)(elemntsNum, con);

		size_t elementsToLoadSave = min(var.length, elemntsNum);

		static if (load == Load.yes) {
			VariableType elementType;
			serializeTypeNoPop!(load)(elementType, con);
			auto conSliceStart = con;
		}

		foreach (i, ref el; var) {
			bool ok = serialize!(load)(el, con);
			if (!ok) {
				return false;
			}
			if (i >= elementsToLoadSave) {
				break;
			}
		}

		static if (load == Load.yes) {
			SizeType oneElementSize = getSerVariableTypeSize(elementType);
			con = conSliceStart[oneElementSize * elementsToLoadSave .. $];
		}
		return true;

	}

	static bool serializeCustomVector(Load load, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		alias ElementType = Unqual!(ForeachType!(T));

		VariableType type = VariableType.array;
		serializeType!(load)(type, con);
		if (type != VariableType.array) {
			return false;
		}

		static if (load == Load.yes) {
			static if (hasMember!(T, "initialize")) {
				var.initialize();
			}
			auto sliceTmp = con;
			SizeType elementsNum;
			serializeSize!(load)(elementsNum, sliceTmp); // Size of whole array data - ignore
			serializeSize!(load)(elementsNum, sliceTmp);

			static if (hasMember!(T, "reserve")) {
				var.reserve(elementsNum);
			}
		}

		return serializeArray!(load)(var, con);
	}

	static bool serializeStringVector(Load load, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		alias ElementType = char;

		VariableType type = VariableType.stringVector;
		serializeType!(load)(type, con);
		if (type != VariableType.stringVector) {
			return false;
		}

		assert(var.length<SizeType.max);
		SizeType size = cast(SizeType)var.length;
		serializeSize!(load)(size, con);

		static if (load == Load.yes) {
			static if (hasMember!(T, "initialize")) {
				var.initialize();
			}
			var = cast(string) con[0 .. size];
			con = con[size .. $];
		} else {
			assert(var[].length == size);
			con ~= cast(ubyte[]) var[];
		}
		return true;
	}

	static bool serializeRange(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(load == Load.no);
		alias ElementType = Unqual!(ForeachType!(T));

		VariableType type = VariableType.staticArray; // Pretend it is staticArray
		serializeType!(load)(type, con);
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
				ok = serialize!(load)(key, con);
				if (!ok) {
					return false;
				}
				ok = serialize!(load)(value, con);
				if (!ok) {
					return false;
				}
				var.add(key, value);
			}
		} else {
			foreach (ref key, ref value; &var.byKeyValue) {
				serialize!(load)(key, con);
				serialize!(load)(value, con);
			}
		}
		return false;
	}

	//////////////////////////////////////////////// HELPERS

	static bool serializeByName(Load load, string name, T, ContainerOrSlice)(ref T var,
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
				bool loaded = serialize!(load)(var, conStartVarTmp);
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

import MSC;

// test basic type
unittest {
	int test = 1;

	CON_UB container;

	//save
	BinarySerializerMaped.serializeWithName!(Load.no, "name",)(test, container);
	assert(container.length == SizeNameType.sizeof + 4 + VariableType.sizeof + 4);

	//reset var
	test = 0;
	//load
	ubyte[] dataSlice = container[];
	BinarySerializerMaped.serializeWithName!(Load.yes, "name",)(test, dataSlice);
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
	BinarySerializerMaped.serializeWithName!(Load.no, "name",)(test, container);
	assert(container.length == SizeNameType.sizeof + 4 + VariableType.sizeof
			+ SizeType.sizeof + 3 * SizeNameType.sizeof + 3 + 3 * VariableType.sizeof + 4 + 8 + 1);
	//writeln("Ratio to ideal minimal size: ", container.length/(4.0f+8.0f+1.0f));
	//reset var
	TestB testB;

	//load
	ubyte[] dataSlice = container[];
	BinarySerializerMaped.serializeWithName!(Load.yes, "name",)(testB, dataSlice);
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
	BinarySerializerMaped.serializeWithName!(Load.no, "name",)(test, container);
	//reset var
	TestB testB;
	//load
	ubyte[] dataSlice = container[];
	BinarySerializerMaped.serializeWithName!(Load.yes, "name",)(testB, dataSlice);

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
	BinarySerializerMaped.serializeWithName!(Load.no, "name",)(test, container);

	//reset var
	TestB testB;
	//load
	ubyte[] dataSlice = container[];
	BinarySerializerMaped.serializeWithName!(Load.yes, "name",)(testB, dataSlice);

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
	BinarySerializerMaped.serializeWithName!(Load.no, "name",)(map, container);

	//reset var
	HashMap!(byte, TestStructB) mapB;
	//load
	ubyte[] dataSlice = container[];
	BinarySerializerMaped.serializeWithName!(Load.yes, "name",)(mapB, dataSlice);
	assert(mapB.get(1) == TestStructB(11, 1));
	assert(mapB.get(7) == TestStructB(77, 7));
}

// test string
unittest {
	import mutils.container.string_intern;

	static struct Test {
		Vector!char aa;
		StringIntern bb;
	}

	static struct TestB {
		Vector!char bb;
		StringIntern aa;
	}

	Test test = Test(Vector!char("aaa"), StringIntern("bbb"));
	Vector!ubyte container;
	//save
	BinarySerializerMaped.serializeWithName!(Load.no, "name",)(test, container);
	//reset var
	TestB testB;
	//load
	ubyte[] dataSlice = container[];
	BinarySerializerMaped.serializeWithName!(Load.yes, "name",)(testB, dataSlice);
	assert(testB.aa=="aaa");
	assert(testB.bb[]=="bbb");

}