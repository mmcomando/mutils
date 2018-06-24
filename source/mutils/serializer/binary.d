module mutils.serializer.binary;

import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.meta;
import std.traits;

public import mutils.serializer.common;
import mutils.container.vector;

/**
 * Serializer to save data in binary format (little endian)
 * If serialized data have to be allocated it is not saved/loaded unless it has "malloc" UDA (@("malloc"))
 */
class BinarySerializer {
	alias SliceElementType = ubyte;
	__gshared static BinarySerializer instance = new BinarySerializer;

	int beginObject(Load load, ContainerOrSlice)(ref ContainerOrSlice con) {
		return 0; // Just to satisfy interface
	}

	void endObject(Load load, ContainerOrSlice)(ref ContainerOrSlice con, int begin) {
	}

	void serializeWithName(Load load, string name, bool useMalloc = false, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		serialize!(load, useMalloc)(var, con);
	}
	/**
	 * Function loads and saves data depending on compile time variable load
	 * If useMalloc is true pointers, arrays, classes will be saved and loaded using Mallocator (there is exception, if vairable is not null it won't be allocated)
	 * T is the serialized variable
	 * ContainerOrSlice is ubyte[] when load==Load.yes 
	 * ContainerOrSlice container supplied by user in which data is stored when load==Load.no(save)
	 * If load==load.skip data is not loaded but slice is pushed fruther
	 */
	void serialize(Load load, bool useMalloc = false, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		commonSerialize!(load, useMalloc)(this, var, con);
	}
	//support for rvalues during load
	void serialize(Load load, bool useMalloc = false, T, ContainerOrSlice)(ref T var,
			ContainerOrSlice con) {
		static assert(load == Load.yes);
		serialize!(load, useMalloc)(var, con);
	}

package:

	void serializeImpl(Load load, bool useMalloc = false, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		static assert((load == Load.skip
				&& is(Unqual!(ForeachType!ContainerOrSlice) == ubyte)) || (load == Load.yes
				&& is(Unqual!(ForeachType!ContainerOrSlice) == ubyte))
				|| (load == Load.no && !isDynamicArray!ContainerOrSlice));
		static assert(!is(T == union), "Type can not be union");
		static assert((!is(T == struct) && !is(T == class)) || !isNested!T,
				"Type can not be nested");

		commonSerialize!(load, useMalloc)(this, var, con);
	}
	//-----------------------------------------
	//--- Basic serializing methods
	//-----------------------------------------
	void serializeBasicVar(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(isBasicType!T);
		static if (load == Load.yes || load == Load.skip) {
			T* tmp = cast(T*) con.ptr;
			static if (load != Load.skip) {
				//On ARM you cannot load floating point value from unaligned memory
				static if (isFloatingPoint!T) {
					ubyte[T.sizeof] t;
					t[0 .. $] = (cast(ubyte*) tmp)[0 .. T.sizeof];
					var = *cast(T*) t;
				} else {
					var = tmp[0];
				}
			}
			con = con[T.sizeof .. $];
		} else {
			ubyte* tmp = cast(ubyte*)&var;
			con ~= tmp[0 .. T.sizeof];
		}
	}

	void serializeStruct(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(is(T == struct));
		serializeClassOrStruct!(load)(var, con);
	}

	void serializeClass(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(is(T == class));
		bool exists = var !is null;
		serialize!(loadOrSkip!load)(exists, con);
		if (!exists) {
			return;
		}
		static if (load == Load.yes) {
			if (var is null)
				var = Mallocator.instance.make!(T);
		} else static if (load == Load.skip) {
			__gshared static T helperObj = new T;
			T beforeVar = var;
			if (var is null)
				var = helperObj;
		}

		serializeClassOrStruct!(load)(var, con);

		static if (load == Load.skip) {
			var = beforeVar;
		}

	}

	void serializeStaticArray(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(isStaticArray!T);
		foreach (i, ref a; var) {
			serialize!(load)(a, con);
		}

	}

	void serializeDynamicArray(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(isDynamicArray!T);
		alias ElementType = Unqual!(ForeachType!(T));
		uint dataLength = cast(uint)(var.length);
		serialize!(loadOrSkip!load)(dataLength, con);
		static if (load == Load.yes) {
			ElementType[] arrData = Mallocator.instance.makeArray!(ElementType)(dataLength);
			foreach (i, ref d; arrData) {
				serialize!(load)(d, con);
			}
			var = cast(T) arrData;
		} else static if (load == Load.skip) {
			T tmp;
			foreach (i; 0 .. dataLength) {
				serialize!(load)(tmp, con);
			}
		} else {
			foreach (i, ref d; var) {
				serialize!(load)(d, con);
			}
		}

	}

	void serializeString(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		serializeCustomVector!(load)(var, con);
	}

	void serializeCustomVector(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		alias ElementType = Unqual!(ForeachType!(T));
		uint dataLength = cast(uint)(var.length);
		serialize!(loadOrSkip!load)(dataLength, con);
		static if (load == Load.yes) {
			static if (hasMember!(T, "initialize")) {
				if (load != Load.skip)
					var.initialize();
			}
			static if (hasMember!(T, "reserve")) {
				if (load != Load.skip)
					var.reserve(dataLength);
			}
			static if (isBasicType!ElementType) {
				ElementType[] arr = (cast(ElementType*) con)[0 .. dataLength];
				if (load != Load.skip)
					var = arr;
				con = con[dataLength * ElementType.sizeof .. $];
			} else {
				foreach (i; 0 .. dataLength) {
					ElementType element;
					serialize!(load)(element, con);
					if (load != Load.skip)
						var ~= element;
				}
			}

		} else {
			foreach (ref d; var) {
				serialize!(load)(d, con);
			}
		}
	}

	void serializeCustomMap(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(isCustomMap!T);

		uint dataLength = cast(uint)(var.length);
		serialize!(loadOrSkip!load)(dataLength, con);

		static if (load == Load.yes) {
			static if (hasMember!(T, "initialize")) {
				if (load != Load.skip)
					var.initialize();
			}
			static if (hasMember!(T, "reserve")) {
				if (load != Load.skip)
					var.reserve(dataLength);
			}
			foreach (i; 0 .. dataLength) {
				T.Key key;
				T.Value value;
				serialize!(load)(key, con);
				serialize!(load)(value, con);
				if (load != Load.skip)
					var.add(key, value);
			}
		} else {
			foreach (ref key, ref value; &var.byKeyValue) {
				serialize!(load)(key, con);
				serialize!(load)(value, con);
			}
		}
	}

	void serializePointer(Load load, bool useMalloc, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		commonSerializePointer!(load, useMalloc)(this, var, con);
	}

	//-----------------------------------------
	//--- Helper methods
	//-----------------------------------------
	void serializeClassOrStruct(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(is(T == struct) || is(T == class));
		foreach (i, ref a; var.tupleof) {
			alias TP = AliasSeq!(__traits(getAttributes, var.tupleof[i]));
			enum bool doSerialize = !hasNoserializeUda!(TP);
			enum bool useMalloc = hasMallocUda!(TP);
			static if (doSerialize) {
				serialize!(load, useMalloc)(a, con);
			}
		}

	}

}

//-----------------------------------------
//--- Tests
//-----------------------------------------

// Helper to avoid GC
private T[n] s(T, size_t n)(auto ref T[n] array) pure nothrow @nogc @safe {
	return array;
}

// test basic types + endianness
unittest {
	int a = 1;
	ubyte b = 3;

	Vector!ubyte container;
	//ubyte[] container;
	ubyte[] dataSlice;

	//save
	BinarySerializer serializer = BinarySerializer.instance;
	serializer.serialize!(Load.no)(a, container);
	serializer.serialize!(Load.no)(b, container);
	assert(container[0] == 1); //little endian
	assert(container[1] == 0);
	assert(container[2] == 0);
	assert(container[3] == 0);
	assert(container[4] == 3);
	assert(container.length == 5);

	//reset var
	a = 0;
	b = 0;

	//load
	dataSlice = container[];
	serializer.serialize!(Load.yes)(a, dataSlice);
	serializer.serialize!(Load.yes)(b, dataSlice);
	assert(a == 1);
	assert(b == 3);
	assert(dataSlice.length == 0);
}

// test structs
unittest {
	static struct TestStruct {
		int a;
		ulong b;
		char c;
	}

	TestStruct test = TestStruct(1, 2, 'c');

	Vector!ubyte container;

	//save
	BinarySerializer serializer = BinarySerializer.instance;
	serializer.serialize!(Load.no)(test, container);
	assert(container[0 .. 4] == [1, 0, 0, 0].s);
	assert(container[4 .. 12] == [2, 0, 0, 0, 0, 0, 0, 0].s);
	assert(container[12] == 'c');
	assert(container.length == 13);

	//reset var
	test = TestStruct.init;

	//load
	serializer.serialize!(Load.yes)(test, container[]);
	assert(test.a == 1);
	assert(test.b == 2);
	assert(test.c == 'c');
}

// test static array
unittest {
	static struct SomeStruct {
		ulong a;
		ubyte b;
	}

	static struct TestStruct {
		SomeStruct[3] a;
	}

	TestStruct test = TestStruct([SomeStruct(1, 1), SomeStruct(2, 2), SomeStruct(3, 3)]);

	Vector!ubyte container;

	//save
	BinarySerializer serializer = BinarySerializer.instance;
	serializer.serialize!(Load.no)(test, container);
	assert(container.length == 3 * 9);

	//reset var
	test = TestStruct.init;

	//load
	serializer.serialize!(Load.yes)(test, container[]);
	assert(test.a == [SomeStruct(1, 1), SomeStruct(2, 2), SomeStruct(3, 3)]);
}

// test dynamic Arrays
unittest {
	static struct TestStruct {
		string str;
		@("malloc") string strMalloc;
		@("malloc") int[] intMalloc;
	}

	static TestStruct test = TestStruct("xx", "ab", [1, 2, 3].s);

	Vector!ubyte container;

	//save
	BinarySerializer serializer = BinarySerializer.instance;
	serializer.serialize!(Load.no)(test, container);
	assert(container.length == 0 + (4 + 2) + (4 + 3 * 4));

	//reset var
	test = TestStruct.init;
	//load
	serializer.serialize!(Load.yes)(test, container[]);
	assert(test.str is null);
	assert(test.strMalloc == "ab");
	assert(test.intMalloc == [1, 2, 3].s);
	Mallocator.instance.dispose(cast(char[]) test.strMalloc);
	Mallocator.instance.dispose(test.intMalloc);
}

// test class
unittest {
	static class TestClass {
		int a;
	}

	static struct TestStruct {
		TestClass ttt;
		@("malloc") TestClass testClass;
		@("malloc") TestClass testClassNull;
	}

	__gshared static TestClass testClass = new TestClass; //nogc
	TestStruct test = TestStruct(testClass, testClass, null);
	test.testClass.a = 4;

	Vector!ubyte container;

	//save
	BinarySerializer serializer = BinarySerializer.instance;
	serializer.serialize!(Load.no)(test, container);
	assert(container.length == 0 + (1 + 4) + 1);

	//reset var
	test = TestStruct.init;
	//load
	serializer.serialize!(Load.yes)(test, container[]);
	assert(test.ttt is null);
	assert(test.testClass.a == 4);
	assert(test.testClassNull is null);
	Mallocator.instance.dispose(test.testClass);
}

// test pointer
unittest {
	static struct TestStructB {
		int a;
	}

	static struct TestStruct {
		@("malloc") TestStructB* pointer;
		@("malloc") TestStructB* pointerNull;
		@("malloc") int[4]* pointerArr;
	}

	int[4]* arr = Mallocator.instance.make!(int[4]);
	TestStructB testTmp;
	TestStruct test = TestStruct(&testTmp, null, arr);
	test.pointer.a = 10;

	Vector!ubyte container;

	//save
	BinarySerializer serializer = BinarySerializer.instance;
	serializer.serialize!(Load.no)(test, container);
	assert(container.length == (1 + 4) + 1 + (1 + 16));

	//reset var
	Mallocator.instance.dispose(arr);
	test = TestStruct.init;
	//load
	serializer.serialize!(Load.yes)(test, container[]);
	assert(test.pointer.a == 10);
	assert(test.pointerNull is null);
	Mallocator.instance.dispose(test.pointer);
	Mallocator.instance.dispose(test.pointerArr);
}

// test custom vector
unittest {
	static struct TestStruct {
		int a;
		void customSerialize(Load load, Serializer, ContainerOrSlice)(Serializer serializer,
				ref ContainerOrSlice con) {
			int tmp = a / 3;
			serializer.serialize!(load)(tmp, con);
			serializer.serialize!(load)(tmp, con);
			serializer.serialize!(load)(tmp, con);
			if (load == Load.yes) {
				a = tmp * 3;
			}
		}
	}

	TestStruct test;
	test.a = 3;
	Vector!ubyte container;

	//save
	BinarySerializer serializer = BinarySerializer.instance;
	serializer.serialize!(Load.no)(test, container);
	assert(container.length == 3 * 4);

	//reset var
	test = TestStruct.init;
	//load
	serializer.serialize!(Load.yes)(test, container[]);
	assert(test.a == 3);
}

// test custom map
unittest {
	import mutils.container.hash_map;

	static struct TestStruct {
		int a;
		int b;
	}

	HashMap!(int, TestStruct) map;
	map.add(1, TestStruct(1, 11));
	map.add(7, TestStruct(7, 77));

	Vector!ubyte container;

	//save
	BinarySerializer serializer = BinarySerializer.instance;
	serializer.serialize!(Load.no)(map, container);
	assert(container.length == 4 + 2 * 4 + 2 * 8); // length + 2*key + 2* value

	//reset var
	map = map.init;
	//load
	serializer.serialize!(Load.yes)(map, container[]);
	assert(map.get(1) == TestStruct(1, 11));
	assert(map.get(7) == TestStruct(7, 77));
}

// test beforeSerialize and afterSerialize
unittest {

	static struct TestStruct {
		ubyte a;
		void beforeSerialize(Load load, Serializer, ContainerOrSlice)(Serializer serializer,
				ref ContainerOrSlice con) {
			ubyte tmp = 10;
			serializer.serialize!(load)(tmp, con);
		}

		void afterSerialize(Load load, Serializer, ContainerOrSlice)(Serializer serializer,
				ref ContainerOrSlice con) {
			ubyte tmp = 7;
			serializer.serialize!(load)(tmp, con);
		}
	}

	TestStruct test;
	test.a = 3;
	Vector!ubyte container;

	//save
	BinarySerializer serializer = BinarySerializer.instance;
	serializer.serialize!(Load.no)(test, container);
	assert(container[] == [10, 3, 7].s);

	//reset var
	test = TestStruct.init;
	//load
	serializer.serialize!(Load.yes)(test, container[]);
	assert(test.a == 3);
}

// test noserialzie
unittest {

	static struct TestStruct {
		@("noserialize") int a;
	}

	static class TestClass {
		@("noserialize") int a;
	}

	__gshared static TestClass testClass = new TestClass;
	TestStruct testStruct;
	Vector!ubyte container;

	//save
	BinarySerializer serializer = BinarySerializer.instance;
	serializer.serialize!(Load.no)(testStruct, container);
	serializer.serialize!(Load.no, true)(testClass, container);
	assert(container.length == 1); //1 because there is check if class exist 

	//reset var
	testStruct = TestStruct.init;
	testClass = TestClass.init;
	//load
	serializer.serialize!(Load.yes)(testStruct, container[]);
	serializer.serialize!(Load.yes, true)(testClass, container[]);
	assert(testStruct.a == 0);
	assert(testClass.a == 0);
}

// test skip
unittest {
	static class TestClass {
		int a;
	}

	static struct TestStructB {
		int a;
		int b;
	}

	static struct TestStruct {
		@("malloc") TestClass a;
		@("malloc") TestStructB* b;
	}

	TestClass testClass = Mallocator.instance.make!(TestClass);
	TestStructB testTmp;
	TestStruct test = TestStruct(testClass, &testTmp);
	testClass.a = 1;
	testTmp.a = 11;
	testTmp.b = 22;

	Vector!ubyte container;

	//save
	BinarySerializer serializer = BinarySerializer.instance;
	serializer.serialize!(Load.no)(test, container);
	assert(container.length == (1 + 4) + (1 + 8));

	//reset var
	Mallocator.instance.dispose(testClass);
	test = TestStruct.init;
	test.b = cast(TestStructB*) 123;
	//skip
	ubyte[] slice = container[];
	serializer.serialize!(Load.skip)(test, slice);
	assert(test.a is null);
	assert(test.b == cast(TestStructB*) 123);
	assert(slice.length == 0);

	//reset var
	test = TestStruct.init;
	//load
	serializer.serialize!(Load.yes)(test, container[]);
	assert(test.a.a == 1);
	assert(test.b.a == 11);
	assert(test.b.b == 22);
	Mallocator.instance.dispose(test.a);
	Mallocator.instance.dispose(test.b);
}
