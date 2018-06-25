module mutils.container.string_intern;

import mutils.container.hash_map;
import mutils.traits : isForeachDelegateWithI;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.traits : Parameters;

private __gshared static HashMap!(const(char)[], StringIntern) gStringInterns;

struct StringIntern {
    private const(char)* strPtr;

    this(const(char)[] fromStr) {
        opAssign(fromStr);
    }

    size_t length() {
        if (strPtr is null) {
            return 0;
        }
        return *cast(size_t*)(strPtr - 8);
    }

    const(char)[] str() {
        return strPtr[0 .. length];
    }

    const(char)[] cstr() {
        return strPtr[0 .. length + 1];
    }

    bool opEquals()(auto ref const StringIntern s) {
        return strPtr == s.strPtr;
    }

    bool opEquals()(auto ref const(char[]) s) {
        return str() == s;
    }

    void opAssign(const(char)[] fromStr) {
        if (fromStr.length == 0) {
            return;
        }
        StringIntern defaultValue;
        StringIntern internedStr = gStringInterns.get(fromStr, defaultValue);

        if (internedStr.length == 0) {
            internedStr.strPtr = allocStr(fromStr).ptr;
            gStringInterns.add(internedStr.str, internedStr);
        }

        strPtr = internedStr.strPtr;
    }

    const(char)[] opSlice() {
        return strPtr[0 .. length];
    }

    private const(char)[] allocStr(const(char)[] fromStr) {
        char[] data = Mallocator.instance.makeArray!(char)(fromStr.length + size_t.sizeof + 1);
        size_t* len = cast(size_t*) data.ptr;
        *len = fromStr.length;
        data[size_t.sizeof .. $ - 1] = fromStr;
        data[$ - 1] = '\0';
        return data[size_t.sizeof .. $ - 1];
    }
}

unittest {
    static assert(StringIntern.sizeof == size_t.sizeof);
    const(char)[] chA = ['a', 'a'];
    char[] chB = ['o', 't', 'h', 'e', 'r'];
    const(char)[] chC = ['o', 't', 'h', 'e', 'r'];
    string chD = "other";

    StringIntern strA;
    StringIntern strB = StringIntern("");
    StringIntern strC = StringIntern("a");
    StringIntern strD = "a";
    StringIntern strE = "aa";
    StringIntern strF = chA;
    StringIntern strG = chB;

    assert(strA == strB);
    assert(strA != strC);
    assert(strC == strD);
    assert(strD != strE);
    assert(strE == strF);

    assert(strD.length == 1);
    assert(strE.length == 2);
    assert(strG.length == 5);

    strA = "other";
    assert(strA == "other");
    assert(strA == chB);
    assert(strA == chC);
    assert(strA == chD);
    assert(strA.str.ptr[strA.str.length] == '\0');
    assert(strA.cstr[$ - 1] == '\0');

    foreach (char c; strA) {
    }
    foreach (int i, char c; strA) {
    }
    foreach (ubyte i, char c; strA) {
    }
    foreach (c; strA) {
    }
}

unittest {
    import mutils.container.hash_map : HashMap;

    HashMap!(StringIntern, StringIntern) map;

    map.add(StringIntern("aaa"), StringIntern("bbb"));
    map.add(StringIntern("aaa"), StringIntern("bbb"));

    assert(map.length == 1);
    assert(map.get(StringIntern("aaa")) == StringIntern("bbb"));

}
