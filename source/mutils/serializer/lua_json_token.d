module mutils.serializer.lua_json_token;

import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.meta;
import std.traits;

import mutils.container.vector_allocator;
import mutils.serializer.common;
import mutils.serializer.lexer_utils;

/**
 * Serializer to save data in json|lua tokens format
 * If serialized data have to be allocated it is not saved/loaded unless it has "malloc" UDA (@("malloc"))
 */
final class JSON_Lua_SerializerToken(bool isJson) {
	alias SliceElementType=TokenData;

	int  beginObject(Load load, ContainerOrSlice)(ref ContainerOrSlice con) {
		serializeCharToken!(load)('{', con);
		return 0;// Just to satisfy interface
	}

	void endObject(Load load, ContainerOrSlice)(ref ContainerOrSlice con, int begin) {
		serializeCharToken!(load)('}', con);
	}

	bool serializeWithName(Load load, string name, bool useMalloc = false, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		static if (load == Load.yes) {
			auto conBegin = con;
			scope (exit)
				con = conBegin; //revert slice

			foreach (iii; 0 .. 1000) {
				string varNa;
				serializeName!(load)(varNa, con);
				bool loaded = false;

				if (name == varNa) {
					try {
						auto tmpCon = con;
						scope (failure)
							con = tmpCon; //revert slice
						serializeImpl!(load, useMalloc)(var, con);
						loaded = true;
					}
					catch (Exception e) {
					}
					return true;
				}
				//scope(exit)Mallocator.instance.dispose(cast(string)varNa);
				if (!loaded) {
					ignoreToMatchingComma!(load)(con);
				}

				if (con[0].isChar(',')) {
					con = con[1 .. $];
				}
				if (con[0].isChar('}')) {
					break;
				}
			}
			return false;

		} else {

			if(!con[$-1].isChar('{')){
				serializeCharToken!(load)(',', con);
			}
			static string tmpName = name;
			serializeName!(load)(tmpName, con);
			assert(tmpName == name);
			serialize!(load, useMalloc)(var, con);
			return true;

		}

	}
	/**
	 * Function loads and saves data depending on compile time variable load
	 * If useMalloc is true pointers, arrays, classes will be saved and loaded using Mallocator
	 * T is the serialized variable
	 * ContainerOrSlice is string when load==Load.yes 
	 * ContainerOrSlice container supplied by user in which data is stored when load==Load.no(save) 
	 */
	void serialize(Load load, bool useMalloc = false, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		try {
			static if (load == Load.yes) {
				//pragma(msg, typeof(con));
				auto sss = NoGcSlice!(ContainerOrSlice)(con);
				serializeImpl!(load, useMalloc)(var, sss);
				con = sss[0 .. $];
			} else {
				serializeImpl!(load, useMalloc)(var, con);
			}
		}
		catch (Exception e) {
		}
	}

	//support for rvalues during load
	void serialize(Load load, bool useMalloc = false, T, ContainerOrSlice)(ref T var,
			ContainerOrSlice con) {
		static assert(load == Load.yes);
		serialize!(load, useMalloc)(var, con);
	}

	__gshared static typeof(this) instance = new typeof(this);

package:

	void serializeImpl(Load load, bool useMalloc = false, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		static assert((load == Load.yes && is(ForeachType!(ContainerOrSlice) == TokenData))
				|| (load == Load.no && is(ForeachType!(ContainerOrSlice) == TokenData)));
		static assert(load != Load.skip, "Skip not supported");
		commonSerialize!(load, useMalloc)(this, var, con);
	}

	//-----------------------------------------
	//--- Basic serializing methods
	//-----------------------------------------
	void serializeBasicVar(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(isBasicType!T);
		static if (is(T == char)) {
			serializeChar!(load)(var, con);
		} else static if (is(T == bool)) {
			serializeBoolToken!(load)(var, con);
		} else {
			static if (load == Load.yes) {
				check!("Wrong token type")(con[0].isAssignableTo!T);
				var = con[0].get!T();
				con = con[1 .. $];
			} else {
				TokenData token;
				token = var;
				con ~= token;
			}
		}
	}

	void serializeStruct(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(is(T == struct));

		serializeCharToken!(load)('{', con);
		static if (load == Load.yes) {
			loadClassOrStruct!(load)(var, con);
		} else {
			saveClassOrStruct!(load)(var, con);
		}

		serializeCharToken!(load)('}', con);

	}

	void serializeClass(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(is(T == class));

		serializeCharToken!(load)('{', con);
		static if (load == Load.yes) {
			var = Mallocator.instance.make!(T);
			loadClassOrStruct!(load)(var, con);
		} else {
			if (var !is null) {
				saveClassOrStruct!(load)(var, con);
			}
		}
		serializeCharToken!(load)('}', con);

	}

	void serializeStaticArray(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(isStaticArray!T);
		serializeCharToken!(load)('[', con);
		foreach (i, ref a; var) {
			serializeImpl!(load)(a, con);
			if (i != var.length - 1) {
				serializeCharToken!(load)(',', con);
			}
		}
		serializeCharToken!(load)(']', con);

	}

	void serializeDynamicArray(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(isDynamicArray!T);
		alias ElementType = Unqual!(ForeachType!(T));
		static if (is(ElementType == char)) {
			static if (load == Load.yes) {
				assert(con[0].type == StandardTokens.string_);

				VectorAllocator!(ElementType, Mallocator) arrData;
				serializeCustomVector!(load)(arrData, con);
				var = cast(T) arrData[];

				//var=con[0].str;
				//con=con[1..$];
			} else {
				TokenData token;
				token = var;
				token.type = StandardTokens.string_;
				con ~= token;
			}
		} else {
			static if (load == Load.yes) {

				VectorAllocator!(ElementType, Mallocator) arrData;
				serializeCustomVector!(load)(arrData, con);
				var = cast(T) arrData[];
			} else {
				serializeCustomVector!(load)(var, con);
			}
		}
	}

	void serializeString(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		serializeCustomVectorString!(load)(var, con);
	}

	void serializeCustomVector(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static if (is(Unqual!(ForeachType!(T)) == char)) {
			serializeCustomVectorString!(load)(var, con);
		} else {
			alias ElementType = Unqual!(ForeachType!(T));
			uint dataLength = cast(uint)(var.length);
			serializeCharToken!(load)('[', con);

			static if (load == Load.yes) {
				static if (hasMember!(T, "initialize")) {
					var.initialize();
				}

				static if (hasMember!(T, "reset")) {
					var.reset();
				}

				while (!con[0].isChar(']')) {
					ElementType element;
					serializeImpl!(load)(element, con);
					var ~= element;
					if (con[0].isChar(',')) {
						serializeCharToken!(load)(',', con);
					} else {
						break;
					}
				}

			} else {
				int i;
				foreach (ref d; var) {
					serializeImpl!(load)(d, con);
					if (i != var.length - 1) {
						serializeCharToken!(load)(',', con);
					}
					i++;
				}

			}
			serializeCharToken!(load)(']', con);
		}
	}

	void serializeCustomMap(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		serializeCharToken!(load)('{', con);
		static if (load == Load.yes) {
			bool ok = !con[0].isChar('}'); // false if no elements inside
			while (ok) {
				T.Key key;
				T.Value value;
				serializeKeyValue!(load)(key, value, con);
				var.add(key, value);

				if (con[0].isChar(',')) {
					serializeCharToken!(load)(',', con);
					ok = !con[0].isChar('}');
				} else {
					break;
				}
			}
		} else {
			size_t i;
			foreach (ref k, ref v; &var.byKeyValue) {
				serializeKeyValue!(load)(k, v, con);
				i++;
				if (i != var.length) {
					serializeCharToken!(load)(',', con);
				}
			}
		}
		serializeCharToken!(load)('}', con);
	}

	void serializeKeyValue(Load load, Key, Value, ContainerOrSlice)(ref Key key,
			ref Value value, ref ContainerOrSlice con) {
		static assert(isStringVector!Key || isNumeric!Key,
				"Map key has to be numeric or char vector.");
		static if (isJson) {
			static if (isStringVector!Key) {
				serializeImpl!(load)(key, con);
			} else static if (load == Load.yes) {
				assert(con[0].type == StandardTokens.string_);
				TokenData tk;
				serializeNumberToken!(load)(tk, con[0].str);
				if (tk.type == StandardTokens.double_) {
					key = cast(Key) tk.double_;
				} else if (tk.type == StandardTokens.long_) {
					key = cast(Key) tk.long_;
				} else {
					assert(0);
				}
				con = con[1 .. $];
			} else { //save
				serializeCharToken!(load)('"', con);
				serializeImpl!(load)(key, con);
				serializeCharToken!(load)('"', con);
			}
			serializeCharToken!(load)(':', con);
			serializeImpl!(load)(value, con);
		} else {
			serializeCharToken!(load)('[', con);
			serializeImpl!(load)(key, con);
			serializeCharToken!(load)(']', con);
			serializeCharToken!(load)('=', con);
			serializeImpl!(load)(value, con);

		}
	}

	void serializePointer(Load load, bool useMalloc, T, ContainerOrSlice)(ref T var,
			ref ContainerOrSlice con) {
		commonSerializePointer!(load, useMalloc)(this, var, con);
	}

	//-----------------------------------------
	//--- Helper methods for basic methods
	//-----------------------------------------

	void loadClassOrStruct(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(load == Load.yes && (is(T == class) || is(T == struct)));

		while (var.tupleof.length > 0) {
			string varNa;
			serializeName!(load)(varNa, con);
			//scope(exit)Mallocator.instance.dispose(cast(string)varNa);
			bool loaded = false;
			foreach (i, ref a; var.tupleof) {
				alias TP = AliasSeq!(__traits(getAttributes, var.tupleof[i]));
				enum bool doSerialize = !hasNoserializeUda!(TP);
				enum bool useMalloc = hasMallocUda!(TP);
				enum string varName = __traits(identifier, var.tupleof[i]);
				static if (doSerialize) {
					if (varName == varNa) {
						try {
							auto tmpCon = con;
							scope (failure)
								con = tmpCon; //revert slice
							serializeImpl!(load, useMalloc)(a, con);
							loaded = true;
							break;
						}
						catch (Exception e) {
						}
					}
				}

			}
			if (!loaded) {
				ignoreToMatchingComma!(load)(con);
			}

			if (con[0].isChar(',')) {
				con = con[1 .. $];
			}
			if (con[0].isChar('}')) {
				break;
			}

		}
	}

	void saveClassOrStruct(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con) {
		static assert(load == Load.no && (is(T == class) || is(T == struct)));
		foreach (i, ref a; var.tupleof) {
			alias TP = AliasSeq!(__traits(getAttributes, var.tupleof[i]));
			enum bool doSerialize = !hasNoserializeUda!(TP);
			enum bool useMalloc = hasMallocUda!(TP);
			enum string varNameTmp = __traits(identifier, var.tupleof[i]);
			static if (doSerialize && (useMalloc || !isMallocType!(typeof(a)))) {
				string varName = cast(string) varNameTmp;
				serializeName!(load)(varName, con);
				serializeImpl!(load, useMalloc)(a, con);

				if (i != var.tupleof.length - 1) {
					serializeCharToken!(load)(',', con);
				}
			} else {
				// hack remove comma if last tuple element was not serializable
				if (i == var.tupleof.length - 1 && var.tupleof.length>1) {// ERROR: if all elements are noserialize
					con.remove(con.length - 1);
				}
			}
		}
	}

	static if (isJson) {

		void serializeName(Load load, ContainerOrSlice)(ref string name, ref ContainerOrSlice con) {

			static if (load == Load.yes) {
				if (con[0].type != StandardTokens.string_) {
					//writelnTokens(con[0..10]);
					//assert(con[0].type == StandardTokens.string_, "Wrong token, there should be key");
					name = null;
					return;
				}
				name = con[0].getUnescapedString;
				con = con[1 .. $];
			} else {
				TokenData token;
				token = name;
				token.type = StandardTokens.string_;
				con ~= token;
			}
			serializeCharToken!(load)(':', con);
		}
	} else {

		void serializeName(Load load, ContainerOrSlice)(ref string name, ref ContainerOrSlice con) {

			static if (load == Load.yes) {
				assert(con[0].type == StandardTokens.identifier);
				name = con[0].str;
				con = con[1 .. $];
			} else {
				TokenData token;
				token = name;
				token.type = StandardTokens.identifier;
				con ~= token;
			}
			serializeCharToken!(load)('=', con);
		}
	}
}
