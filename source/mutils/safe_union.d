module mutils.safe_union;

import std.algorithm : max;
import std.conv : to;
import std.format : format, FormatSpec, formatValue;
import std.meta : staticIndexOf;
import std.range : put;
import std.traits : ForeachType, hasMember, isArray, Parameters, ReturnType;

import mutils.serializer.binary;

/**
 * Union of ConTypes... 
 * Ensures correct access with assert
 */
struct SafeUnion(bool makeFirstParDefaultOne, ConTypes...) {
	alias FromTypes = ConTypes;
	static assert(FromTypes.length > 0, "Union has to have members.");

	union {
		private FromTypes values;
	}

	mixin(getCode!(FromTypes));
	//enum Types{...}    //from mixin
	alias Types = TypesM; // alias used to give better autocompletion in IDE-s

	Types currentType = (makeFirstParDefaultOne) ? Types._0 : Types.none;

	/**
	 * Constuctor supporting direcs assigment of Type
	 */
	this(T)(T obj) {
		static assert(properType!T, "Given Type is not present in union");
		set(obj);
	}

	void opAssign(SafeUnion!(makeFirstParDefaultOne, ConTypes) obj) {
		this.tupleof = obj.tupleof;
	}
	//void opAssign(this);
	void opAssign(T)(T obj) {
		static assert(properType!T, "Given Type is not present in union");
		set(obj);
	}

	/**
	 * returns given type with check
	 */
	@nogc nothrow auto get(T)() {
		static assert(properType!T, "Given Type is not present in union");

		enum index = staticIndexOf!(T, FromTypes);
		assert(currentType == index, "Got type which is not currently bound.");
		return &values[index];
	}

	/**
	 * Returns enum value for Type
	 */
	@nogc nothrow bool isType(T)() {
		static assert(properType!T, "Given Type is not present in union");
		enum index = staticIndexOf!(T, FromTypes);
		return currentType == index;
	}

	/**
	 * Returns enum value for Type
	 */
	static Types getEnum(T)() {
		static assert(properType!T, "Given Type is not present in union");
		return cast(Types) staticIndexOf!(T, FromTypes);
	}

	/**
	 * Sets given Type
	 */
	@nogc nothrow auto set(T)(T obj) {
		static assert(properType!T, "Given Type is not present in union");
		enum index = staticIndexOf!(T, FromTypes);
		currentType = cast(Types) index;
		values[index] = obj;
	}

	auto ref apply(alias fun)() {
	sw:
		switch (currentType) {
			foreach (i, Type; FromTypes) {
		case i:
				return fun(values[i]);
			}

		default:
			assert(0);
		}
	}

	/**
	 * Support for serialization
	 */
	void customSerialize(Load load, Serializer, COS)(Serializer serializer, ref COS con) {
		auto begin = serializer.beginObject!(load)(con);
		scope (exit)
			serializer.endObject!(load)(con, begin);

		serializer.serializeWithName!(load, "type")(currentType, con);
	sw:
		final switch (currentType) {
			foreach (i, Type; FromTypes) {
		case i:
				serializer.serializeWithName!(load, FromTypes[i].stringof)(values[i], con);
				break sw;
			}
		case Types.none:
			break;
		}
	}

	/**
	 * Preety print
	 */
	void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt) {
		put(sink, "SafeUnion(");

	sw:
		final switch (currentType) {
			foreach (i, Type; FromTypes) {
		case i:
				formatValue(sink, values[i], fmt);
				break sw;
			}
		case Types.none:
			put(sink, "none");
			break;
		}

		put(sink, ")");
	}

	/**
	 * Checks if opDispatch supports given function
	 */
	static bool checkOpDispach(string funcName)() {
		bool ok = true;
		foreach (Type; FromTypes) {
			ok = ok && hasMember!(Type, funcName);
		}
		return ok;
	}

	/**
	 * Forwards call to union member
	 * Works only if all union members has this function and this function has the same return type and parameter types
	 * Can not be made opDispatch because it somehow breakes hasMember trait
	 */
	auto call(string funcName, Args...)(auto ref Args args)
			if (checkOpDispach!(funcName)) {
		mixin("alias CompareReturnType=ReturnType!(FromTypes[0]." ~ funcName ~ ");");
		mixin("alias CompareParametersTypes=Parameters!(FromTypes[0]." ~ funcName ~ ");");
		foreach (Type; FromTypes) {
			mixin("enum bool typeOk=is(ReturnType!(Type." ~ funcName ~ ")==CompareReturnType);");
			mixin(
					"enum bool parametersOk=is(Parameters!(Type." ~ funcName
					~ ")==CompareParametersTypes);");
			static assert(typeOk, "Return type " ~ CompareReturnType.stringof
					~ " of '" ~ funcName ~ "' has to be the same in every union member.");
			static assert(parametersOk, "Parameter types " ~ CompareParametersTypes.stringof
					~ " of '" ~ funcName ~ "' have to be the same in every union member.");
		}
	sw:
		switch (currentType) {
			foreach (i, Type; FromTypes) {
		case i:
				auto val = &values[i];
				mixin("return val." ~ funcName ~ "(args);");
			}
		default:
			assert(0);
		}
	}

package:

	/** 
	 * Generates enum for stored Types
	 */
	private static string getCode(FromTypes...)() {

		string code = "enum TypesM:ubyte{";
		foreach (i, Type; FromTypes) {
			code ~= format("_%d=%d,", i, i);
		}
		code ~= "none}";
		return code;
	}

	/**
	 *  Checks if Type is in union Types
	 */
	private static bool properType(T)() {
		return staticIndexOf!(T, FromTypes) != -1;
	}
}
/// Example Usage
unittest {
	struct Triangle {
		int add(int a) {
			return a + 10;
		}
	}

	struct Rectangle {
		int add(int a) {
			return a + 100;
		}
	}

	static uint strangeID(T)(T obj) {
		static if (is(T == Triangle)) {
			return 123;
		} else static if (is(T == Rectangle)) {
			return 14342;
		} else {
			assert(0);
		}
	}

	alias Shape = SafeUnion!(false, Triangle, Rectangle);
	Shape shp;
	shp.set(Triangle());
	assert(shp.isType!Triangle);
	assert(!shp.isType!Rectangle);
	assert(shp.call!("add")(6) == 16); //Better error messages 
	assert(shp.apply!strangeID == 123);
	//shp.get!(Rectangle);//Crash
	shp.set(Rectangle());
	assert(shp.call!("add")(6) == 106);
	assert(shp.apply!strangeID == 14342);
	shp.currentType = shp.Types.none;
	//shp.apply!strangeID;//Crash
	//shp.add(6);//Crash
	final switch (shp.currentType) {
	case shp.getEnum!Triangle:
		break;
	case Shape.getEnum!Rectangle:
		break;
	case Shape.Types.none:
		break;
	}

}
