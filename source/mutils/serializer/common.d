module mutils.serializer.common;

import std.algorithm : stripLeft;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.string : indexOf;
import std.traits;

import mutils.serializer.lexer_utils;

/// Runtime check, throws nogc exception on error
static void check(string str = "Parsing Error")(bool ok) {
	enum hardCheck = false; // if true assert on error else throw Exception
	static if (hardCheck) {
		assert(ok, str);
	} else {
		shared static immutable Exception e = new Exception(str);
		if (!ok) {
			throw e;
		}
	}
}

/// Enum to check if data is loaded or saved
enum Load {
	no = 0,
	yes = 1,
	skip = 2,

}

/// Checks if type have to be allocated by serializer
auto isMallocType(T)() {
	static if (isDynamicArray!T || isPointer!T || is(T == class)) {
		return true;
	} else {
		return false;
	}
}

/// Checks if in user defined attributes(UDA) there is malloc string
/// "malloc" string UDA indicates that data should be allocated by serializer
auto hasMallocUda(Args...)() {
	bool hasMalloc = false;
	foreach (Arg; Args) {
		static if (is(typeof(Arg) == string) && Arg == "malloc") {
			hasMalloc = true;
		}
	}
	return hasMalloc;
}

/// Checks if in user defined attributes(UDA) there is noserialize string
/// "noserialize" string UDA indicates that data should not be serialzied by serializer
auto hasNoserializeUda(Args...)() {
	bool hasMalloc = false;
	foreach (Arg; Args) {
		static if (is(typeof(Arg) == string) && Arg == "noserialize") {
			hasMalloc = true;
		}
	}
	return hasMalloc;
}

bool isStringVector(T)() {
	static if (is(T == struct) && is(Unqual!(ForeachType!T) == char)) {
		return true;
	} else {
		return false;
	}
}
/// Checks if type can be treated as vector ex. replace int[] with MyArray!int
bool isCustomVector(T)() {
	static if (is(T == struct) && hasMember!(T, "opOpAssign") && hasMember!(T,
			"add") && hasMember!(T, "length")) {
		return true;
	} else {
		return false;
	}
}
/// Checks if type can be treated as map
bool isCustomMap(T)() {
	static if (is(T == struct) && hasMember!(T, "byKey") && hasMember!(T,
			"byValue") && hasMember!(T, "byKeyValue") && hasMember!(T, "add")
			&& hasMember!(T, "isIn")) {
		return true;
	} else {
		return false;
	}
}
///Returns Load.yes when load is Load.yes or Load.skip
Load loadOrSkip(Load load)() {
	static if (load == Load.yes || load == Load.skip) {
		return Load.yes;
	} else {
		return load;

	}
}

void commonSerialize(Load load, bool useMalloc = false, Serializer, T, ContainerOrSlice)(
		Serializer ser, ref T var, ref ContainerOrSlice con) {
	static if (__traits(compiles, var.beforeSerialize!(load)(ser, con))) {
		var.beforeSerialize!(load)(ser, con);
	}

	static if (hasMember!(T, "customSerialize")) {
		var.customSerialize!(load)(ser, con);
	} else static if (isBasicType!T) {
		ser.serializeBasicVar!(load)(var, con);
	} else static if (isStringVector!T) {
		ser.serializeString!(load)(var, con);
	} else static if (isCustomVector!T) {
		ser.serializeCustomVector!(load)(var, con);
	} else static if (isCustomMap!T) {
		ser.serializeCustomMap!(load)(var, con);
	} else static if (is(T == struct)) {
		ser.serializeStruct!(load)(var, con);
	} else static if (isStaticArray!T) {
		ser.serializeStaticArray!(load)(var, con);
	} else static if (useMalloc && isMallocType!T) {
		static if (isDynamicArray!T) {
			ser.serializeDynamicArray!(load)(var, con);
		} else static if (is(T == class)) {
			ser.serializeClass!(load)(var, con);
		} else static if (isPointer!T) {
			ser.serializePointer!(load, useMalloc)(var, con);
		} else {
			static assert(0);
		}
	} else static if (!useMalloc && isMallocType!T) {
		//don't save, leave default value
	} else static if (is(T == interface)) {
		//don't save, leave default value
	} else {
		static assert(0, "Type can not be serialized");
	}

	static if (hasMember!(T, "afterSerialize")) {
		var.afterSerialize!(load)(ser, con);
	}
}

/// Struct to let BoundsChecking Without GC
struct NoGcSlice(T) {
	shared static immutable Exception e = new Exception("BoundsChecking NoGcException");
	T slice;
	alias slice this;

	//prevent NoGcSlice in NoGcSlice, NoGcSlice!(NoGcSlice!(T))
	static if (!hasMember!(T, "slice")) {
		T opSlice(X, Y)(X start, Y end) {
			if (start >= slice.length || end > slice.length) {
				//assert(0);
				throw e;
			}
			return slice[start .. end];
		}

		size_t opDollar() {
			return slice.length;
		}
	}
}

void commonSerializePointer(Load load, bool useMalloc, Serializer, T, ContainerOrSlice)(
		Serializer ser, ref T var, ref ContainerOrSlice con) {
	static assert(isPointer!T);
	alias PointTo = typeof(*var);
	bool exists = var !is null;
	ser.serializeImpl!(loadOrSkip!load)(exists, con);
	if (!exists) {
		return;
	}
	static if (load == Load.yes) {
		if (var is null)
			var = Mallocator.instance.make!(PointTo);
	} else static if (load == Load.skip) {
		__gshared static PointTo helperObj;
		T beforeVar = var;
		if (var is null)
			var = &helperObj;
	}
	ser.serializeImpl!(load, useMalloc)(*var, con);
	static if (load == Load.skip) {
		var = beforeVar;
	}

}

void writelnTokens(TokenData[] tokens) {
	import mutils.stdio : writeln;

	writeln("--------");
	foreach (tk; tokens) {
		writeln(tk);
	}
}

void tokensToCharVectorPreatyPrint(Lexer, Vec)(TokenData[] tokens, ref Vec vec) {
	int level = 0;
	void addSpaces() {
		foreach (i; 0 .. level)
			vec ~= cast(char[]) "    ";
	}

	foreach (tk; tokens) {
		if (tk.isChar('{')) {
			Lexer.toChars(tk, vec);
			level++;
			vec ~= '\n';
			addSpaces();
		} else if (tk.isChar('}')) {
			level--;
			vec ~= '\n';
			addSpaces();
			Lexer.toChars(tk, vec);
		} else if (tk.isChar(',')) {
			Lexer.toChars(tk, vec);
			vec ~= '\n';
			addSpaces();
		} else {
			Lexer.toChars(tk, vec);
		}

	}
}

//-----------------------------------------
//--- Helper methods for string format
//-----------------------------------------

void serializeCustomVectorString(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
	alias ElementType = Unqual!(ForeachType!(T));
	static assert(is(ElementType == char));

	static if (load == Load.yes) {
		var = con[0].getUnescapedString;
		con = con[1 .. $];
	} else {
		TokenData token;
		token = cast(string) var[];
		token.type = StandardTokens.string_;
		con ~= token;
	}
}

void serializeCharToken(Load load, ContainerOrSlice)(char ch, ref ContainerOrSlice con) {
	static if (load == Load.yes) {
		check(con[0].type == StandardTokens.character && con[0].isChar(ch));
		con = con[1 .. $];
	} else {
		TokenData token;
		token = ch;
		con ~= token;
	}
}

void serializeBoolToken(Load load, ContainerOrSlice)(ref bool var, ref ContainerOrSlice con) {
	static if (load == Load.yes) {
		check(con[0].type == StandardTokens.identifier || con[0].type == StandardTokens.long_);
		if (con[0].type == StandardTokens.identifier) {
			if (con[0].str == "true") {
				var = true;
			} else if (con[0].str == "false") {
				var = false;
			} else {
				check(false);
			}
		} else {
			if (con[0].long_ == 0) {
				var = false;
			} else {
				var = true;
			}
		}

		con = con[1 .. $];
	} else {
		TokenData token;
		token.type = StandardTokens.identifier;
		token.str = (var) ? "true" : "false";
		con ~= token;
	}
}

void ignoreBraces(Load load, ContainerOrSlice)(ref ContainerOrSlice con,
		char braceStart, char braceEnd) {
	static assert(load == Load.yes);
	assert(con[0].isChar(braceStart));
	con = con[1 .. $];
	int nestageLevel = 1;
	while (con.length > 0) {
		TokenData token = con[0];
		con = con[1 .. $];
		if (token.type != StandardTokens.character) {
			continue;
		}
		if (token.isChar(braceStart)) {
			nestageLevel++;
		} else if (token.isChar(braceEnd)) {
			nestageLevel--;
			if (nestageLevel == 0) {
				break;
			}
		}
	}
}

void ignoreToMatchingComma(Load load, ContainerOrSlice)(ref ContainerOrSlice con) {
	static assert(load == Load.yes);
	int nestageLevel = 0;
	//scope(exit)writelnTokens(con);
	while (con.length > 0) {
		TokenData token = con[0];
		if (token.type != StandardTokens.character) {
			con = con[1 .. $];
			continue;
		}
		if (token.isChar('[') || token.isChar('{')) {
			nestageLevel++;
		} else if (token.isChar(']') || token.isChar('}')) {
			nestageLevel--;
		}

		if (nestageLevel < 0 || (nestageLevel == 0 && token.isChar(','))) {
			break;
		} else {
			con = con[1 .. $];
		}
	}
}
