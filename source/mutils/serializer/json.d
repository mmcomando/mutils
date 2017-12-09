module mutils.serializer.json;

import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.meta;

public import mutils.serializer.common;

import mutils.serializer.lexer_utils;


/**
 * Serializer to save data in json format
 * If serialized data have to be allocated it is not saved/loaded unless it has "malloc" UDA (@("malloc"))
 */
class JSONSerializer{
	/**
	 * Function loads and saves data depending on compile time variable load
	 * If useMalloc is true pointers, arrays, classes will be saved and loaded using Mallocator
	 * T is the serialized variable
	 * ContainerOrSlice is char[] when load==Load.yes 
	 * ContainerOrSlice container supplied by user in which data is stored when load==Load.no(save) 
	 */
	void serialize(Load load,bool useMalloc=false, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		try{
			static if(load==Load.yes){
				JSONLexer lex=JSONLexer(cast(string)con, true, true);
				auto tokens=lex.tokenizeAll();				
				//load
				__gshared static JSONSerializerToken serializer= new JSONSerializerToken();
				serializer.serialize!(Load.yes, useMalloc)(var,tokens[]);		
				tokens.clear();
			}else{
				__gshared static JSONSerializerToken serializer= new JSONSerializerToken();
				TokenDataVector tokens;
				serializer.serialize!(Load.no, useMalloc)(var,tokens);
				tokensToCharVectorPreatyPrint!(JSONLexer)(tokens[],con);
				tokens.clear();
			}
		}catch(Exception e){}
	}

	//support for rvalues during load
	void serialize(Load load,bool useMalloc=false, T, ContainerOrSlice)(ref T var,ContainerOrSlice con){
		static assert(load==Load.yes);
		serialize!(load,useMalloc)(var,con);		
	}

	__gshared static JSONSerializer instance= new JSONSerializer();

}


//-----------------------------------------
//--- Tests
//-----------------------------------------

// Helper to avoid GC
private T[n] s(T, size_t n)(auto ref T[n] array) pure nothrow @nogc @safe{return array;}

import mutils.container.vector;
// test formating
unittest{
	
	static struct TestStruct{
		int a;
		int b;
		@("malloc") string c;
	}
	TestStruct test;
	Vector!char container;
	string str=`
	
{
    "b"   :145    ,  "a":  1,   "c"               :   


"asdasdas asdasdas asdasd asd"
}
`;
	
	
	//load
	__gshared static JSONSerializer serializer= new JSONSerializer();
	serializer.serialize!(Load.yes)(test,cast(char[])str);
	//writeln(test);
	assert(test.a==1);
	assert(test.b==145);
	assert(test.c=="asdasdas asdasdas asdasd asd");
	Mallocator.instance.dispose(cast(char[])test.c);
}

// test formating
unittest{
	static struct TestStructB{
		int a;
	}
	static struct TestStruct{
		int a;
		int b;
		TestStructB bbb;
	}
	TestStruct test;
	Vector!char container;
	string str=`
	
{
    "b"   :145,
	"a":{},
	"xxxxx":{},
	"bbb":13,
	"www":{}

`;
	
	//load
	__gshared static JSONSerializer serializer= new JSONSerializer();
	serializer.serialize!(Load.yes)(test,cast(char[])str);
	
	assert(test.a==0);
	assert(test.b==145);
}

// test basic types
unittest{
	static struct TestStructA{
		int a;
		@("malloc") string b;
		int c;
	}
	static struct TestStruct{
		int a;
		TestStructA aa;
		int b;
		@("malloc") string c;
	}
	TestStruct test;
	test.a=1;
	test.b=2;
	test.c="asdasdasda asd asda";
	test.aa.a=11;
	test.aa.c=22;
	test.aa.b="xxxxx";
	Vector!char container;
	
	//save
	JSONSerializer.instance.serialize!(Load.no)(test,container);
	//writeln(container[]);
	
	//reset var
	test=TestStruct.init;
	
	//load
	JSONSerializer.instance.serialize!(Load.yes)(test,container[]);
	assert(test.a==1);
	assert(test.b==2);
	assert(test.c=="asdasdasda asd asda");
	assert(test.aa.a==11);
	assert(test.aa.c==22);
	assert(test.aa.b=="xxxxx");
	Mallocator.instance.dispose(cast(char[])test.aa.b);
	Mallocator.instance.dispose(cast(char[])test.c);
}

// test arrays
unittest{
	static struct TestStructB{
		@("malloc") string a="ala";
	}
	static struct TestStruct{
		int[3] a;
		@("malloc") int[] b;
		Vector!int c;
		Vector!TestStructB d;
		float e;
	}
	TestStruct test;
	test.a=[1,2,3].s;
	test.b=[11,22,33].s;
	test.c~=[1,2,3,4,5,6,7].s;
	test.d~=[TestStructB("asddd"),TestStructB("asd12dd"),TestStructB("asddaszdd")].s;
	test.e=32.52f;
	Vector!char container;
	
	//save
	JSONSerializer.instance.serialize!(Load.no)(test,container);
	
	//reset var
	test=TestStruct.init;
	
	//load
	JSONSerializer.instance.serialize!(Load.yes)(test,container[]);
	//writeln(test);
	assert(test.a==[1,2,3].s);
	assert(test.b==[11,22,33].s);
	assert(test.c[]==[1,2,3,4,5,6,7].s);
	Mallocator.instance.dispose(test.b);
	Mallocator.instance.dispose(cast(char[])test.d[0].a);
	Mallocator.instance.dispose(cast(char[])test.d[1].a);
	Mallocator.instance.dispose(cast(char[])test.d[2].a);
}

// test map
unittest{
	import mutils.container.hash_map;
	import mutils.container.hash_set;
	static struct TestInner{
		int a;
		ubyte b;
	}

	static struct Test{
		HashMap!(Vector!(char), TestInner) map;
		HashMap!(int, int) mapInt;
	}

	Vector!char key1;
	Vector!char key2;
	key1~=cast(char[])"aaaaaaAA";
	key2~=cast(char[])"BBBBbbbb";

	Test test;
	test.map.add(key1, TestInner(1, 2));
	test.map.add(key2, TestInner(3, 5));
	test.mapInt.add(100, 10);
	test.mapInt.add(200, 20);
	Vector!char container;
	
	//save
	JSONSerializer.instance.serialize!(Load.no)(test,container);

	//reset var
	test=test.init;
	
	//load
	JSONSerializer.instance.serialize!(Load.yes)(test,container[]);

	assert(test.map.get(key1)==TestInner(1, 2));
	assert(test.map.get(key2)==TestInner(3, 5));
	assert(test.mapInt.get(100)==10);
	assert(test.mapInt.get(200)==20);
}

// test class
unittest{
	static class TestClass{
		int a;
		ubyte b;
	}
	__gshared static TestClass test=new TestClass;
	test.a=11;
	test.b='b';
	Vector!char container;
	
	//save
	__gshared static JSONSerializer serializer= new JSONSerializer();
	serializer.serialize!(Load.no,true)(test,container);

	//reset var
	test=null;

	//load
	serializer.serialize!(Load.yes,true)(test,container[]);
	assert(test.a==11);
	assert(test.b=='b');
}

// test nothing
unittest{
	static struct TestStruct{
	}
	__gshared static TestStruct test;
	Vector!char container;
	
	//save
	JSONSerializer.instance.serialize!(Load.no,true)(test, container);
	//load
	JSONSerializer.instance.serialize!(Load.yes,true)(test,container[]);
}

//-----------------------------------------
//--- Lexer 
//-----------------------------------------

struct JSONLexer{
	enum Token{
		notoken=StandardTokens.notoken,
		white=StandardTokens.white,
		character=StandardTokens.character,
		identifier=StandardTokens.identifier,
		string_=StandardTokens.string_,
		double_=StandardTokens.double_,
		long_=StandardTokens.long_,
	}
	
	alias characterTokens=AliasSeq!('[',']','{','}','(',')',',',':');

	string code;
	string slice;
	bool skipUnnecessaryWhiteTokens=true;
	
	uint line;
	uint column;
	
	@disable this();
	
	this(string code, bool skipWhite, bool skipComments){
		this.code=code;
		slice=this.code[];
		skipUnnecessaryWhiteTokens=skipWhite;
	}	
	
	void clear(){
		code=null;
		line=column=0;
		slice=null;
	}	
	
	TokenData checkNextToken(){
		auto sliceCopy=slice;
		auto token=getNextToken();
		slice=sliceCopy;
		return token;
	}
	
	private TokenData getNextTokenImpl(){
		TokenData token;
		switch(slice[0]){
			//------- character tokens ------------------------
			foreach(ch;characterTokens){
				case ch:
			}
			token=slice[0];
			slice=slice[1..$];
			return token;
			
			
			//--------- white tokens --------------------------
			foreach(ch;whiteTokens){
				case ch:
			}
			serializeWhiteTokens!(true)(token,slice);
			return token;
			
			//------- escaped strings -------------------------
			case '"':
				serializeStringToken!(true)(token,slice);
				return token;
				
				//------- something else -------------------------
			default:
				break;
		}
		if(isIdentifierFirstChar(slice[0])){
			serializeIdentifier!(true)(token,slice);
		}else if((slice[0]>='0' && slice[0]<='9') || slice[0]=='-'){
			serializeNumberToken!(true)(token,slice);
		}else{
			slice=null;
		}
		return token;
		
	}
	
	TokenData getNextToken(){
		TokenData token;
		string sliceCopy=slice[];
		scope(exit){
			token.line=line;
			token.column=column;
			updateLineAndCol(line,column,sliceCopy,slice);
		}
		while(slice.length>0){
			token=getNextTokenImpl();
			if(skipUnnecessaryWhiteTokens && token.type==Token.white){
				token=TokenData.init;
				continue;
			}
			break;
		}
		return token;
	}
	
	
	static void toChars(Vec)(TokenData token, ref Vec vec){
		
		final switch(cast(Token)token.type){
			case Token.long_:
			case Token.double_:
				serializeNumberToken!(false)(token,vec);
				break;
			case Token.character:
				vec~=token.ch;
				break;
			case Token.white:
			case Token.identifier:
				vec~=cast(char[])token.str;
				break;
			case Token.string_:
				vec~='"';
				vec~=cast(char[])token.getEscapedString();
				vec~='"';
				break;
				
			case Token.notoken:
				assert(0);
		}
		
	}
	
	
}

unittest{
	string code=`{ [ ala: "asdasd", ccc:123.3f]}"`;
	JSONLexer json=JSONLexer(code,true,true);
	TokenData token;
	token.type=StandardTokens.identifier;
	token.str="asd";
}

unittest{
	void testOutputTheSame(string str){
		string sliceCopy=str;
		JSONLexer json=JSONLexer(str, false,false);
		Vector!TokenData tokens=json.tokenizeAll();
		
		JSONLexer json2=JSONLexer([], false,false);
		//writeln(tokens[]);
		//writeln(json2.tokensToString(tokens[0..$-1]),"|\n\n\n",sliceCopy,"|");
		assert(json2.tokensToString(tokens[0..$-1])==sliceCopy);
		
	}
	testOutputTheSame("  12345 ");
	testOutputTheSame(`{ [ ala :  "asdasd",
	 ccc: 
123]  }  `);
}


import mutils.serializer.lua_json_token;

alias JSONSerializerToken= JSON_Lua_SerializerToken!(true);



//-----------------------------------------
//--- Tests
//-----------------------------------------
import mutils.container.vector;
// test formating
unittest{
	string str=` 12345 `;
	int a;
	JSONLexer lex=JSONLexer(cast(string)str,true,true);
	auto tokens=lex.tokenizeAll();
	
	
	//load
	__gshared static JSONSerializerToken serializer= new JSONSerializerToken();
	serializer.serialize!(Load.yes)(a,tokens[]);
	assert(a==12345);
	
	tokens.clear();
	serializer.serialize!(Load.no)(a,tokens);
	assert(tokens[0].type==StandardTokens.long_);
	assert(tokens[0].long_==12345);
	
	
}

unittest{
	string str=`
	
{
"wwwww":{"w":[1,2,3]},
    "b"   :145    ,  "a":  1,   "c"               :   


"asdasdas asdasdas asdasd asd"
}
`;
	static struct TestStruct{
		int a;
		int b;
		@("malloc") string c;
	}
	TestStruct test;
	JSONLexer lex=JSONLexer(cast(string)str,true,true);
	auto tokens=lex.tokenizeAll();	
	
	//load
	__gshared static JSONSerializerToken serializer= new JSONSerializerToken();
	auto ttt=tokens[];
	serializer.serialize!(Load.yes)(test,ttt);
	assert(test.a==1);
	assert(test.b==145);
	assert(test.c=="asdasdas asdasdas asdasd asd");
	
	tokens.clear();
	
	serializer.serialize!(Load.no)(test,tokens);
	
	assert(tokens.length==13);
	Mallocator.instance.dispose(cast(char[])test.c);
}







// test formating
unittest{
	static struct TestStructB{
		int a;
	}
	static struct TestStruct{
		int a;
		int b;
		TestStructB bbb;
	}
	TestStruct test;
	//Vector!char container;
	string str=`
 
 {
 "b"   :145,
 "a":{},
 "xxxxx":{},
 "bbb":13,
 "www":{}

 `;
	
	JSONLexer lex=JSONLexer(cast(string)str,true,true);
	auto tokens=lex.tokenizeAll();	
	//load
	__gshared static JSONSerializerToken serializer= new JSONSerializerToken();
	serializer.serialize!(Load.yes)(test,tokens[]);
	
	assert(test.a==0);
	assert(test.b==145);
}


// test basic types
unittest{
	static struct TestStructA{
		int a;
		@("malloc") string b;
		int c;
	}
	static struct TestStruct{
		int a;
		TestStructA aa;
		int b;
		@("malloc") string c;
	}
	TestStruct test;
	test.a=1;
	test.b=2;
	test.c="asdasdasda asd asda";
	test.aa.a=11;
	test.aa.c=22;
	test.aa.b="xxxxx";
	Vector!TokenData tokens;
	
	//save
	__gshared static JSONSerializerToken serializer= new JSONSerializerToken();
	serializer.serialize!(Load.no)(test,tokens);
	
	//reset var
	test=TestStruct.init;
	
	//load
	serializer.serialize!(Load.yes)(test,tokens[]);
	assert(test.a==1);
	assert(test.b==2);
	assert(test.c=="asdasdasda asd asda");
	assert(test.aa.a==11);
	assert(test.aa.c==22);
	assert(test.aa.b=="xxxxx");
	Mallocator.instance.dispose(cast(char[])test.aa.b);
	Mallocator.instance.dispose(cast(char[])test.c);
}

// test arrays
unittest{
	static struct TestStructB{
		@("malloc") string a="ala";
	}
	static struct TestStruct{
		int[3] a;
		@("malloc") int[] b;
		Vector!int c;
		Vector!TestStructB d;
		float e;
	}
	TestStruct test;
	test.a=[1,2,3].s;
	test.b=[11,22,33].s;
	test.c~=[1,2,3,4,5,6,7].s;
	test.d~=[TestStructB("asddd"),TestStructB("asd12dd"),TestStructB("asddaszdd")].s;
	test.e=32.52f;
	//Vector!char container;
	Vector!TokenData tokens;
	

	//save
	JSONSerializerToken.instance.serialize!(Load.no)(test,tokens);
	
	//reset var
	test=TestStruct.init;
	
	//load
	JSONSerializerToken.instance.serialize!(Load.yes)(test,tokens[]);
	assert(test.a==[1,2,3].s);
	assert(test.b==[11,22,33].s);
	assert(test.c[]==[1,2,3,4,5,6,7].s);
	Mallocator.instance.dispose(test.b);
	Mallocator.instance.dispose(cast(char[])test.d[0].a);
	Mallocator.instance.dispose(cast(char[])test.d[1].a);
	Mallocator.instance.dispose(cast(char[])test.d[2].a);
}



// test class
unittest{
	static class TestClass{
		int a;
		ubyte b;
	}
	__gshared static TestClass test=new TestClass;
	test.a=11;
	test.b='b';
	Vector!TokenData tokens;
	
	//save
	__gshared static JSONSerializerToken serializer= new JSONSerializerToken();
	serializer.serialize!(Load.no,true)(test, tokens);
	//reset var
	test=null;
	
	//load
	serializer.serialize!(Load.yes,true)(test,tokens[]);
	
	assert(test.a==11);
	assert(test.b=='b');
}
