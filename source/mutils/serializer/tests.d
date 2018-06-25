module mutils.serializer.tests;

import std.meta;

import mutils.container.vector : Vector;
import mutils.serializer.binary;
import mutils.serializer.binary_maped;
import mutils.serializer.json;

// Minimum requirements for all serializers:
// - fields serialized in order must work
// - @("noserialize") support
// - has to have default serializer instance (Serializer.instance)
// - supports customSerialize

import MSC;

auto getContainer(Serializer)() {
    static if (is(Serializer.SliceElementType == ubyte)) {
        return CON_UB();
    } else static if (is(Serializer.SliceElementType == char)) {
        return CON_C();
    } else {
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

    void customSerialize(Load load, Serializer, COS)(Serializer serializer, ref COS con) {
        auto begin = serializer.beginObject!(load)(con);
        scope (exit)
            serializer.endObject!(load)(con, begin);

        serializer.serializeWithName!(load, "varA")(a, con);
        serializer.serializeWithName!(load, "varB")(b, con);
        serializer.serializeWithName!(load, "varC")(c, con);

    }
}

// Test common serialzier properties
unittest {
    alias SerializersToTest = AliasSeq!(BinarySerializer,
            BinarySerializerMaped, JSONSerializerToken);

    enum TestA[3] arrA = [TestA(1, 2), TestA(3, 4), TestA(5, 6)];

    foreach (Serializer; SerializersToTest) {
        testSerializerInOut(Serializer.instance, 4, 4);
        testSerializerInOut(Serializer.instance, TestA(1, 2), TestA(1, 2));
        testSerializerInOut(Serializer.instance, TestB(3, 4, TestA(1, 2)),
                TestB(3, 4, TestA(1, 2)));
        testSerializerInOut(Serializer.instance, TestC(3, 4, TestA(1, 2)),
                TestC(3, 4, TestA(1, 2)));

        testSerializerInOut(Serializer.instance, Vector!TestA(arrA), Vector!TestA(arrA));

        testSerializerBeginEnd(Serializer.instance);
    }
}

struct TestA_Diff {
    int xxx;
    byte a;
}

struct TestB_Diff {
    long b;
    TestA_Diff c;
    ushort a;
}

struct TestB_Diff2 {
}

// Test out of order loading,loading without present members, loading with different types
unittest {
    alias SerializersToTest = AliasSeq!(BinarySerializerMaped, JSONSerializerToken);

    enum TestA[3] arrA = [TestA(1, 2), TestA(3, 4), TestA(5, 6)];

    foreach (Serializer; SerializersToTest) {
        testSerializerInOut(Serializer.instance, TestA(1, 2), TestA_Diff(0, 1));
        testSerializerInOut(Serializer.instance, TestB(3, 4, TestA(1, 2)),
                TestB_Diff(4, TestA_Diff(0, 1), 3));
        testSerializerInOut(Serializer.instance, TestB(3, 4, TestA(1, 2)), TestB_Diff2());

        testSerializerInOut(Serializer.instance, Vector!TestA(arrA), Vector!TestA(arrA));

        testSerializerBeginEnd(Serializer.instance);
    }
}
