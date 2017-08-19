module mutils.serializer.json_token;

import std.meta;
import std.stdio : writeln;

import mutils.serializer.common;
import mutils.serializer.lexer;

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

	Vector!char code;
	string slice;
	bool skipUnnecessaryWhiteTokens=true;

	uint line;
	uint column;
	
	@disable this();
	
	this(string code, bool skipWhite, bool skipComments){
		this.code~=cast(char[])code;
		slice=cast(string)this.code[];
		skipUnnecessaryWhiteTokens=skipWhite;
	}	
	
	void clear(){
		code.clear();
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
}

// test arrays
unittest{
	static struct TestStructB{
		@("malloc") string a=cast(string)"ala";
	}
	static struct TestStruct{
		int[3] a;
		@("malloc") int[] b;
		Vector!int c;
		Vector!TestStructB d;
		float e;
	}
	TestStruct test;
	test.a=[1,2,3];
	test.b=[11,22,33];
	test.c~=[1,2,3,4,5,6,7];
	test.d~=[TestStructB(cast(string)"asddd"),TestStructB(cast(string)"asd12dd"),TestStructB(cast(string)"asddaszdd")];
	test.e=32.52f;
	//Vector!char container;
	Vector!TokenData tokens;

	
	//save
	__gshared static JSONSerializerToken serializer= new JSONSerializerToken();
	serializer.serialize!(Load.no)(test,tokens);

	//reset var
	test=TestStruct.init;
	
	//load
	serializer.serialize!(Load.yes)(test,tokens[]);
	assert(test.a==[1,2,3]);
	assert(test.b==[11,22,33]);
	assert(test.c[]==[1,2,3,4,5,6,7]);
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
