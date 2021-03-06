﻿module mutils.serializer.lua;

import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.meta;

import mutils.container.vector;
public import mutils.serializer.common;
import mutils.serializer.lexer_utils;
import mutils.serializer.lua_json_token;

//  COS==ContainerOrSlice

/**
 * Serializer to save data in lua format
 * If serialized data have to be allocated it is not saved/loaded unless it has "malloc" UDA (@("malloc"))
 */
class LuaSerializer {
	/**
	 * Function loads and saves data depending on compile time variable load
	 * If useMalloc is true pointers, arrays, classes will be saved and loaded using Mallocator
	 * T is the serialized variable
	 * COS is char[] when load==Load.yes 
	 * COS container supplied by user in which data is stored when load==Load.no(save) 
	 */
	void serialize(Load load, bool useMalloc = false, T, COS)(ref T var, ref COS con) {
		try {
			static if (load == Load.yes) {
				LuaLexer lex = LuaLexer(cast(string) con, true, true);
				auto tokens = lex.tokenizeAll();
				//load
				__gshared static LuaSerializerToken serializer = new LuaSerializerToken();
				serializer.serialize!(Load.yes, useMalloc)(var, tokens[]);
				tokens.clear();
			} else {
				__gshared static LuaSerializerToken serializer = new LuaSerializerToken();
				TokenDataVector tokens;
				serializer.serialize!(Load.no, useMalloc)(var, tokens);
				tokensToCharVectorPreatyPrint!(LuaLexer)(tokens[], con);
				tokens.clear();
			}
		}
		catch (Exception e) {
		}
	}

	//support for rvalues during load
	void serialize(Load load, bool useMalloc = false, T, COS)(ref T var, COS con) {
		static assert(load == Load.yes);
		serialize!(load, useMalloc)(var, con);
	}

	__gshared static LuaSerializer instance = new LuaSerializer();

}

//-----------------------------------------
//--- Tests
//-----------------------------------------

// test formating
// test customVector of char serialization
unittest {
	string pa1 = "aaa aaa";
	string pa2 = "ddd";
	string pa3 = "ccc";
	static struct TestStruct {
		struct Project {
			Vector!char name;
			Vector!char path;
			Vector!char texPath;
			int ccc;
		}

		Vector!Project projects;
	}

	TestStruct test;
	TestStruct.Project p1, p2;
	p1.path ~= cast(char[]) pa1;
	p1.ccc = 100;

	p2.name ~= cast(char[]) pa2;
	p2.path ~= cast(char[]) pa3;
	p2.ccc = 200;
	test.projects ~= p1;
	test.projects ~= p2;
	Vector!char container;

	//save
	LuaSerializer.instance.serialize!(Load.no)(test, container);

	//reset var
	test = TestStruct.init;

	//load
	LuaSerializer.instance.serialize!(Load.yes)(test, container[]);
	assert(test.projects.length == 2);
	assert(test.projects[0].name[] == "");
	assert(test.projects[0].path[] == "aaa aaa");
	assert(test.projects[0].ccc == 100);

	assert(test.projects[1].name[] == "ddd");
	assert(test.projects[1].path[] == "ccc");
	assert(test.projects[1].ccc == 200);
}

unittest {

	static struct TestStruct {
		int a;
		int b;
		@("malloc") string c;
	}

	TestStruct test;
	Vector!char container;
	string str = `
	
{
    b   =145    ,  a=  1,   c               =  


"asdasdas asdasdas asdasd asd"
}
`;

	//load
	LuaSerializer.instance.serialize!(Load.yes)(test, cast(char[]) str);
	//writeln(test);
	assert(test.a == 1);
	assert(test.b == 145);
	assert(test.c == "asdasdas asdasdas asdasd asd");
}

//-----------------------------------------
//--- Lexer 
//-----------------------------------------

struct LuaLexer {
	enum Token {
		notoken = StandardTokens.notoken,
		white = StandardTokens.white,
		character = StandardTokens.character,
		identifier = StandardTokens.identifier,
		string_ = StandardTokens.string_,
		double_ = StandardTokens.double_,
		long_ = StandardTokens.long_,
		comment_multiline = StandardTokens.comment_multiline,
		comment_line = StandardTokens.comment_line,
	}

	alias characterTokens = AliasSeq!('[', ']', '{', '}', '(', ')', ',', '=');

	string code;
	string slice;
	bool skipUnnecessaryWhiteTokens = true;
	bool skipComments = true;

	uint line;
	uint column;

	@disable this();

	this(string code, bool skipWhite, bool skipComments) {
		this.code = code;
		slice = this.code[];
		skipUnnecessaryWhiteTokens = skipWhite;
		this.skipComments = skipComments;
	}

	void clear() {
		code = null;
		line = column = 0;
		slice = null;
	}

	TokenData checkNextToken() {
		auto sliceCopy = slice;
		auto token = getNextToken();
		slice = sliceCopy;
		return token;
	}

	private TokenData getNextTokenImpl() {
		TokenData token;
		switch (slice[0]) {
			//------- character tokens ------------------------
			foreach (ch; characterTokens) {
		case ch:
			}
			token = slice[0];
			slice = slice[1 .. $];
			return token;

			//--------- white tokens --------------------------
			foreach (ch; whiteTokens) {
		case ch:
			}
			serializeWhiteTokens!(true)(token, slice);
			return token;

			//------- escaped strings -------------------------
		case '"':
			serializeStringToken!(true)(token, slice);
			return token;

			//------- comment -------------------------
		case '/':
			check(slice.length > 1);
			if (slice[1] == '*') {
				serializeCommentMultiline!(true)(token, slice);
			} else if (slice[1] == '/') {
				serializeCommentLine!(true)(token, slice);
			} else {
				check(false);
			}
			return token;

			//------- something else -------------------------
		default:
			break;
		}
		if (isIdentifierFirstChar(slice[0])) {
			serializeIdentifier!(true)(token, slice);
		} else if ((slice[0] >= '0' && slice[0] <= '9') || slice[0] == '-') {
			serializeNumberToken!(true)(token, slice);
		} else {
			slice = null;
		}
		return token;
	}

	TokenData getNextToken() {
		TokenData token;
		string sliceCopy = slice[];
		scope (exit) {
			token.line = line;
			token.column = column;
			updateLineAndCol(line, column, sliceCopy, slice);
		}
		while (slice.length > 0) {
			token = getNextTokenImpl();
			if ((skipComments && token.isComment)
					|| (skipUnnecessaryWhiteTokens && token.type == Token.white)) {
				token = TokenData.init;
				continue;
			}
			break;
		}
		return token;
	}

	static void toChars(Vec)(TokenData token, ref Vec vec) {

		final switch (cast(Token) token.type) {
		case Token.long_:
		case Token.double_:
			serializeNumberToken!(false)(token, vec);
			break;
		case Token.comment_multiline:
			serializeCommentMultiline!(false)(token, vec);
			break;
		case Token.comment_line:
			serializeCommentLine!(false)(token, vec);
			break;
		case Token.character:
			vec ~= token.ch;
			break;
		case Token.white:
		case Token.identifier:
			vec ~= cast(char[]) token.str;
			break;
		case Token.string_:
			vec ~= '"';
			vec ~= cast(char[]) token.getEscapedString();
			vec ~= '"';
			break;

		case Token.notoken:
			assert(0);
		}

	}

}

unittest {
	string code = `{ [ ala= "asdasd",
// hkasdf sdfasdfs sdf  &8 9 (( 7 ^ 	
 ccc=123.3f  /* somethingsdfsd 75#^ */  ]}"`;
	LuaLexer lua = LuaLexer(code, true, false);
	auto tokens = lua.tokenizeAll();
	//writelnTokens(tokens[]);
}

alias LuaSerializerToken = JSON_Lua_SerializerToken!(false);

//-----------------------------------------
//--- Tests
//-----------------------------------------

// test formating
// test customVector of char serialization
unittest {
	string pa1 = "aaa aaa";
	string pa2 = "ddd";
	static struct TestStruct {
		struct Project {
			Vector!char path;
			int ccc;
		}

		Vector!Project projects;
	}

	TestStruct test;
	TestStruct testB;
	TestStruct.Project p1;
	TestStruct.Project p2;

	p1.path ~= cast(char[]) pa1;
	p1.ccc = 100;
	p2.path ~= cast(char[]) pa2;
	p2.ccc = 200;
	test.projects ~= p1;
	test.projects ~= p2;
	Vector!TokenData tokens;
	//save
	LuaSerializerToken.instance.serialize!(Load.no)(test, tokens); // Tokens are valid as long as test is not changed

	//Vector!char vv;
	//tokensToCharVectorPreatyPrint!(LuaLexer)(tokens[], vv);

	//load
	LuaSerializerToken.instance.serialize!(Load.yes)(testB, tokens[]);
	assert(testB.projects.length == 2);
	assert(testB.projects[0].ccc == 100);
	assert(testB.projects[0].path[] == cast(char[]) "aaa aaa");
	assert(testB.projects[1].ccc == 200);
	assert(testB.projects[1].path[] == cast(char[]) "ddd");
}
