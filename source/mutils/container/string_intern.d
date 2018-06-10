module mutils.container.string_intern;

import mutils.container.hash_map2;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import mutils.traits : isForeachDelegateWithI;
import std.traits : Parameters;

struct StringIntern {
    private __gshared HashMap!(const(char)[], StringIntern) internStrings;
    private const(char)[] str;

    this(const(char)[] fromStr) {
        opAssign(fromStr);
    }

    const(char)[] get() {
        return str;
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

    // foreach support
   /* int opApply(DG)(scope DG dg) {
        int result;
        static if (isForeachDelegateWithI!DG) {
            foreach (Parameters!(DG)[0] i, char c; str) {
                result = dg(i, c);
                if (result)
                    break;
            }
        } else {
            foreach (char c; str) {
                result = dg(c);
                if (result)
                    break;
            }
        }

        return result;
    }*/

    const(char)[] opSlice(){
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
    import mutils.container.hash_map2 : HashMap;

    HashMap!(StringIntern, StringIntern) map;

    map.add(StringIntern("aaa"), StringIntern("bbb"));
    map.add(StringIntern("aaa"), StringIntern("bbb"));
    
    assert(map.length==1);
    assert(map.get(StringIntern("aaa"))==StringIntern("bbb"));

}