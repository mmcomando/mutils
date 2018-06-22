module mutils.serializer.tests;

import std.meta;

import mutils.serializer.binary;
import mutils.serializer.binary_maped;
import mutils.serializer.json;

// Minimum requirements for all serializers:
// - fields serialized in order must work
// - @("noserialize") support
// - has to have default serializer instance (Serializer.instance)
// - supports customSerialize

// Helper to avoid GC
private T[n] s(T, size_t n)(auto ref T[n] array) pure nothrow @nogc @safe {
    return array;
}

import MSC;

auto getContainer(Serializer)() {
    static if (is(Serializer.SliceElementType == ubyte)) {
        return CON_UB();
    } else static if (is(Serializer.SliceElementType == char)) {
        return CON_C();
    } else {
        import mutils.container.vector : Vector;
        return Vector!(Serializer.SliceElementType)();
    }
}

void testSerializerInOut(Serializer, VariableIn, VariableOut)(
        ref Serializer serializer, VariableIn varIn, VariableOut varOut) {
    auto container = getContainer!Serializer;
    serializer.serialize!(Load.no)(varIn, container);
    assert(container.length > 0);

    VariableOut outVarTest;
    serializer.serialize!(Load.yes)(outVarTest, container[]);
    assert(outVarTest == varOut);
}

void testSerializerBeginEnd(Serializer)(ref Serializer serializer) {
    int numA = 1;
    long numB = 2;
    int numC = 3;

    auto container = getContainer!Serializer;

    auto begin = serializer.beginObject!(Load.no)(container);
    serializer.serialize!(Load.no)(numA, container);
    serializer.serialize!(Load.no)(numB, container);
    serializer.serialize!(Load.no)(numC, container);
    serializer.endObject!(Load.no)(container, begin);

    numA = 0;
    numB = 0;
    numC = 0;
    import std.stdio;

    auto slice = container[];

    begin = serializer.beginObject!(Load.yes)(slice);
    serializer.serialize!(Load.yes)(numA, slice);
    serializer.serialize!(Load.yes)(numB, slice);
    serializer.serialize!(Load.yes)(numC, slice);
    serializer.endObject!(Load.yes)(slice, begin);

    assert(numA == 1);
    assert(numB == 2);
    assert(numC == 3);
}

struct TestA {
    int a;
    int b;
}

struct TestB {
    int a;
    int b;
    TestA c;
}

struct TestC {
    int a;
    int b;
    TestA c;

    	void customSerialize(Load load, Serializer, ContainerOrSlice)(Serializer serializer,
				ref ContainerOrSlice con) {
			auto begin = serializer.beginObject!(load)(con);
			scope (exit)
				serializer.endObject!(load)(con, begin);

			serializer.serializeWithName!(load, "varA")(a, con);
			serializer.serializeWithName!(load, "varB")(b, con);
			serializer.serializeWithName!(load, "varC")(c, con);

		}
}

unittest {
    alias SerializersToTest = AliasSeq!(BinarySerializer, BinarySerializerMaped, JSONSerializerToken);

    foreach (Serializer; SerializersToTest) {
        testSerializerInOut(Serializer.instance, 4, 4);
        testSerializerInOut(Serializer.instance, TestA(1, 2), TestA(1, 2));
        testSerializerInOut(Serializer.instance, TestB(3, 4, TestA(1, 2)),
                TestB(3, 4, TestA(1, 2)));
        testSerializerInOut(Serializer.instance, TestC(3, 4, TestA(1, 2)),                TestC(3, 4, TestA(1, 2)));
                

        testSerializerBeginEnd(Serializer.instance);
    }
}
