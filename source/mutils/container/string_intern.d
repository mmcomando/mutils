module mutils.container.string_intern;

import mutils.container.hash_map2;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;



struct StringIntern {
    private __gshared HashMap!(const(char)[], StringIntern) internStrings;
    private const(char)[] str;

    this(const(char)[] fromStr) {
        opAssign(fromStr);
    }

    bool opEquals()(auto ref const StringIntern s) const {
        return str.ptr == s.str.ptr;
    }

    bool opEquals()(auto ref const(char[]) s) const {
        return str == s;
    }

    void opAssign(const(char)[] fromStr) {
        if (fromStr.length == 0) {
            return;
        }
        StringIntern defaultValue;
        StringIntern internedStr = internStrings.get(fromStr, defaultValue);

        if (internedStr.str.length == 0) {
            internedStr.str = allocStr(fromStr);
            internStrings.add(internedStr.str, internedStr);
        }

        str = internedStr.str;
    }

    const(char)[] get() {
        return str;
    }

    private const(char)[] allocStr(const(char)[] fromStr) {
        char[] data = Mallocator.instance.makeArray!(char)(fromStr.length + 1);
        data[0 .. $ - 1] = fromStr;
        data[$ - 1] = '\0';
        return data[0 .. $ - 1];
    }
}

import std.stdio;

unittest {
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

    strA = "other";
    assert(strA == "other");
    assert(strA == chB);
    assert(strA == chC);
    assert(strA == chD);
    assert(strA.str.ptr[strA.str.length] == '\0');
}
