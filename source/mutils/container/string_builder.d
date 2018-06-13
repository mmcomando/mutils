module mutils.container.string_builder;

import std.meta;
import std.stdio;
import std.traits;

import mutils.container.string_intern;
import mutils.container.string_tmp;
import mutils.container.vector;
import mutils.conv : num2str;
import mutils.safe_union;

struct StringBuilder {

    alias ElementData = SafeUnion!(true, char, string, const(char)[], StringIntern, long, double);
    static struct Element {
        ElementData data;
    }

    Vector!Element elements;

    this(T)(T obj) {
        createNew(obj, elements, false);
    }

    void reserve(size_t size) {
        elements.reserve(size);
    }

    StringBuilder opBinaryRight(string op, T)(T lhs) {
        static assert(op == "~", "Only concatenation operator is supported");
        StringBuilder newBuilder;
        createNew(lhs, newBuilder.elements, false);
        return newBuilder;
    }

    StringBuilder opBinary(string op, T)(T lhs) {
        static assert(op == "~", "Only concatenation operator is supported");
        StringBuilder newBuilder;
        createNew(lhs, newBuilder.elements, true);
        return newBuilder;
    }

    void createNew(T)(T rhs, ref Vector!Element arrToAdd, bool addToRight) {
        static assert(isProperType!T, "Concatenation of given type not supported");

        static if (is(T == char[])) {
            auto rhsValue = cast(const(char)[]) rhs;
        } else static if (isIntegral!T) {
            auto rhsValue = cast(long) rhs;
        } else static if (isFloatingPoint!T) {
            auto rhsValue = cast(double) rhs;
        } else {
            auto rhsValue = rhs;
        }

        Element element = Element(ElementData(rhsValue));
        arrToAdd.reserve(elements.length + 1);
        if (addToRight) {
            arrToAdd ~= elements[];
            arrToAdd ~= element;
        } else {
            arrToAdd ~= element;
            arrToAdd ~= elements[];
        }
    }

    size_t getRequiredSize() {
        size_t size;
        foreach (ref e; elements) {
            switch (e.data.currentType) {
            case ElementData.getEnum!char:
                size += 1;
                break;
            case ElementData.getEnum!string:
                string str = *e.data.get!string;
                size += str.length;
                break;
            case ElementData.getEnum!(const(char)[]):
                const(char)[] str = *e.data.get!(const(char)[]);
                size += str.length;
                break;
            case ElementData.getEnum!StringIntern:
                StringIntern str = *e.data.get!StringIntern;
                size += str.length;
                break;
            case ElementData.getEnum!long:
                char[64] buff;
                long num = *e.data.get!long;
                string str = num2str(num, buff[]);
                size += str.length;
                break;
            case ElementData.getEnum!double:
                char[64] buff;
                double num = *e.data.get!double;
                string str = num2str(num, buff[]);
                size += str.length;
                break;
            default:
                break;
            }
        }
        return size + 1;
    }

    StringTmp toStringTmp(char[] buffer = null) {
        size_t charsAdded;

        size_t requiredSize = getRequiredSize();
        if (buffer.length < requiredSize) {
            buffer = StringTmp.allocateStr(requiredSize);
        }

        foreach (ref e; elements) {
            switch (e.data.currentType) {
            case ElementData.getEnum!char:
                buffer[charsAdded] = *e.data.get!char;
                charsAdded++;
                break;
            case ElementData.getEnum!string:
                string str = *e.data.get!string;
                buffer[charsAdded .. charsAdded + str.length] = str;
                charsAdded += str.length;
                break;
            case ElementData.getEnum!(const(char)[]):
                const(char)[] str = *e.data.get!(const(char)[]);
                buffer[charsAdded .. charsAdded + str.length] = str;
                charsAdded += str.length;
                break;
            case ElementData.getEnum!StringIntern:
                StringIntern str = *e.data.get!StringIntern;
                buffer[charsAdded .. charsAdded + str.length] = str.get();
                charsAdded += str.length;
                break;
            case ElementData.getEnum!long:
                char[64] buff;
                long num = *e.data.get!long;
                string str = num2str(num, buff[]);
                buffer[charsAdded .. charsAdded + str.length] = str;
                charsAdded += str.length;
                break;
            case ElementData.getEnum!double:
                char[64] buff;
                double num = *e.data.get!double;
                string str = num2str(num, buff[]);
                buffer[charsAdded .. charsAdded + str.length] = str;
                charsAdded += str.length;
                break;
            default:
                break;
            }
        }
        buffer[requiredSize - 1] = '\0';
        if (buffer.length < requiredSize) {
            return StringTmp(buffer, true);
        }
        return StringTmp(buffer[0 .. requiredSize], false);
    }

    static bool isProperType(T)() {
        enum index = is(T == char[]) || isNumeric!T || staticIndexOf!(T, ElementData.FromTypes);
        return index != -1;
    }

}

unittest {
    char[4] chars = ['h', 'a', 's', ' '];
    char[256] buffer;
    StringBuilder str = StringBuilder("String ") ~ chars[] ~ 'n' ~ 'o' ~ StringIntern(
            " power ") ~ 2 ~ " be m" ~ 8.0f;

    auto tmpStr = str.toStringTmp(buffer);
    assert(tmpStr.str == "String has no power 2 be m8\0");
}
