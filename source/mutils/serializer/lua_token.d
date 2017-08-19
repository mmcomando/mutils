module mutils.serializer.lua_token;

import std.meta;
import std.stdio : writeln;

import mutils.serializer.common;
import mutils.serializer.lexer;


struct LuaLexer{
	enum Token{
		notoken=StandardTokens.notoken,
		white=StandardTokens.white,
		character=StandardTokens.character,
		identifier=StandardTokens.identifier,
		string_=StandardTokens.string_,
		double_=StandardTokens.double_,
		long_=StandardTokens.long_,
		comment_multiline=StandardTokens.comment_multiline,
		comment_line=StandardTokens.comment_line,
	}

	alias characterTokens=AliasSeq!('[',']','{','}','(',')',',','=');
	
	Vector!char code;
	string slice;
	bool skipUnnecessaryWhiteTokens=true;
	bool skipComments=true;

	uint line;
	uint column;
	
	@disable this();
	
	this(string code, bool skipWhite, bool skipComments){
		this.code~=cast(char[])code;
		slice=cast(string)this.code[];
		skipUnnecessaryWhiteTokens=skipWhite;
		this.skipComments=skipComments;
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
				
				//------- comment -------------------------
			case '/':
				check(slice.length>1);
				if(slice[1]=='*'){
					serializeCommentMultiline!(true)(token,slice);
				}else if(slice[1]=='/'){
					serializeCommentLine!(true)(token,slice);
				}else{
					check(false);
				}
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
			if(
				(skipComments && token.isComment) ||
				(skipUnnecessaryWhiteTokens && token.type==Token.white)
			){
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
			case Token.comment_multiline:
				serializeCommentMultiline!(false)(token,vec);
				break;
			case Token.comment_line:
				serializeCommentLine!(false)(token,vec);
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
	string code=`{ [ ala= "asdasd",
// hkasdf sdfasdfs sdf  &8 9 (( 7 ^ 	
 ccc=123.3f  /* somethingsdfsd 75#^ */  ]}"`;
	LuaLexer lua=LuaLexer(code,true,false);
	auto tokens=lua.tokenizeAll();
	//writelnTokens(tokens[]);
}





import mutils.serializer.lua_json_token;
alias LuaSerializerToken= JSON_Lua_SerializerToken!(false);


//-----------------------------------------
//--- Tests
//-----------------------------------------
import mutils.container.vector;
// test formating
// test customVector of char serialization
unittest{
	static struct TestStruct{
		struct Project
		{
			Vector!char path;
			int ccc;
		}
		
		Vector!Project projects;
	}
	TestStruct test;
	TestStruct.Project p1;
	TestStruct.Project p2;

	p1.path~=['a', 'a', 'a', ' ', 'a', 'a', 'a'];
	p1.ccc=100;
	p2.path~=['d', 'd', 'd'];
	p2.ccc=200;
	test.projects~=p1;
	test.projects~=p2;
	Vector!TokenData tokens;
	
	//save
	__gshared static LuaSerializerToken serializer= new LuaSerializerToken();
	serializer.serialize!(Load.no)(test,tokens);

	//Vector!char vv;
	//tokensToCharVectorPreatyPrint!(LuaLexer)(tokens[], vv);
	//writeln(vv[]);
	
	//reset var
	test=TestStruct.init;
	
	//load
	serializer.serialize!(Load.yes)(test,tokens[]);
	assert(test.projects.length==2);
	assert(test.projects[0].ccc==100);
	assert(test.projects[0].path[]==cast(char[])"aaa aaa");
	assert(test.projects[1].ccc==200);
	assert(test.projects[1].path[]==cast(char[])"ddd");
}
