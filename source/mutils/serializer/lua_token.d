module mutils.serializer.lua_token;

import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.meta;
import std.traits;
import std.conv;
import std.algorithm:stripLeft;
import std.string:indexOf;
import std.stdio : writeln;

public import mutils.serializer.common;
public import mutils.serializer.lexer;


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

	alias TokenDataVector=Vector!(TokenData);
	alias characterTokens=AliasSeq!('[',']','{','}','(',')',',','=');
	
	
	
	Vector!char code;
	bool skipUnnecessaryWhiteTokens=true;
	string slice;
	TokenData lastToken;
	uint line;
	uint column;
	
	@disable this();
	
	this(string code, bool skipWhite){
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
	
	TokenData getNextToken(){
		string sliceCopy=slice[];
		TokenData token;
		if(slice.length==0){
			return token;
		}
		switch(slice[0]){
			//------- character tokens ------------------------
			foreach(ch;characterTokens){
				case ch:
			}
			token=slice[0];
			slice=slice[1..$];
			goto end;
			
			
			//--------- white tokens --------------------------
			foreach(ch;whiteTokens){
				case ch:
			}
			serializeWhiteTokens!(true)(token,slice);
			goto end;

			//------- escaped strings -------------------------
			case '"':
				serializeStringToken!(true)(token,slice);
				goto end;

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
				goto end;
				
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
		
	end:
		//------- add line information -------------------------
		token.line=line;
		token.column=column;
		updateLineAndCol(line,column,sliceCopy,slice);
		if(skipUnnecessaryWhiteTokens==true && token.type==Token.white){
			return getNextToken();
		}
		//writeln(slice);
		return token;
	}
	
	void saveToken(TokenData token){
		toChars(token, code);
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
	
	
	void serialize(bool load, Container)(ref TokenData token, ref Container con){
		static if(load==true){
			token=getNextToken();
		}else{
			saveToken(token);
		}
		
	}
	
	void printAllTokens(){
		TokenData token;
		while(token.type!=Token.notoken){
			token=getNextToken();
			writeln(token);
		}
	}
	
	TokenDataVector tokenizeAll(){
		TokenDataVector tokens;
		do{
			tokens~=getNextToken();
		}while(tokens[$-1].type!=Token.notoken);
		
		return tokens;
	}
	
	string tokensToString(TokenData[] tokens){
		foreach(tk;tokens){
			saveToken(tk);}
		return cast(string)code[];
	}
	
	
}

unittest{
	string code=`{ [ ala= "asdasd",
// hkasdf sdfasdfs sdf  &8 9 (( 7 ^ 	
 ccc=123.3f  /* somethingsdfsd 75#^ */  ]}"`;
	LuaLexer lua=LuaLexer(code,true);
	auto tokens=lua.tokenizeAll();
	writelnTokens(tokens[]);
}





/**
 * Serializer to save data in lua format
 * If serialized data have to be allocated it is not saved/loaded unless it has "malloc" UDA (@("malloc"))
 */
class LuaSerializerToken{
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
				auto sss=NoGcSlice!(ContainerOrSlice)(con);
				serializeImpl!(load,useMalloc)(var, sss);
				con=sss[0..$];
			}else{
				serializeImpl!(load,useMalloc)(var, con);
			}
		}catch(Exception e){}
	}
	
	//support for rvalues during load
	void serialize(Load load,bool useMalloc=false, T, ContainerOrSlice)(ref T var,ContainerOrSlice con){
		static assert(load==Load.yes);
		serialize!(load,useMalloc)(var,con);		
	}
	
	
	
	
	__gshared static LuaSerializerToken instance = new LuaSerializerToken;
	
package:
	
	void serializeImpl(Load load,bool useMalloc=false, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(
			(load==Load.yes && is(ForeachType!(ContainerOrSlice)==TokenData)) ||
			(load==Load.no  && is(ForeachType!(ContainerOrSlice)==TokenData))
			);
		static assert(load!=Load.skip,"Skip not supported");
		
		commonSerialize!(load,useMalloc)(this,var,con);
	}

	//-----------------------------------------
	//--- Basic serializing methods
	//-----------------------------------------
	void serializeBasicVar(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(isBasicType!T);
		static if (is(T==char)) {
			ser.serializeChar!(load)(var, con);
		}else{
			static if (load == Load.yes) {
				check!("Wrong token type")(con[0].isType!T);
				var = con[0].get!T();
				con=con[1..$];
			} else {
				TokenData token;
				token=var;
				con ~= token;
			}
		}
	}
	
	void serializeStruct(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(is(T == struct));
		
		
		serializeCharToken!(load)('{' ,con);
		static if(load==Load.yes){
			loadClassOrStruct!(load)(var,con);	
		}else{
			saveClassOrStruct!(load)(var,con);
		}
		
		serializeCharToken!(load)('}' ,con);
		
	}
	
	
	void serializeClass(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(is(T==class));
		
		serializeCharToken!(load)('{' ,con);
		static if(load==Load.yes){
			var=Mallocator.instance.make!(T);
			loadClassOrStruct!(load)(var,con);		
		}else{
			if(var !is null){
				saveClassOrStruct!(load)(var,con);
			}
		}
		serializeCharToken!(load)('}' ,con);
		
	}
	
	
	void serializeStaticArray(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(isStaticArray!T);
		serializeCharToken!(load)('[',con);
		foreach (i, ref a; var) {
			serializeImpl!(load)(a,con);
			if(i!=var.length-1){
				serializeCharToken!(load)(',',con);
			}
		}
		serializeCharToken!(load)(']',con);
		
	}
	
	
	void serializeDynamicArray(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(isDynamicArray!T);
		alias ElementType=Unqual!(ForeachType!(T));
		static if(is(ElementType==char)){
			static if (load == Load.yes) {
				assert(con[0].type==StandardTokens.string_);
				var=con[0].str;
				con=con[1..$];
			} else {
				TokenData token;
				token=var;
				token.type=StandardTokens.string_;
				con ~= token;
			}
		}else{	
			static if(load==Load.yes){
				import mutils.container.vector_allocator;
				VectorAllocator!(ElementType, Mallocator) arrData;				
				serializeCustomVector!(load)(arrData, con);
				var=cast(T)arrData[];
			}else{			
				serializeCustomVector!(load)(var, con);				
			}
		}
	}
	
	
	
	
	void serializeCustomVector(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static if(is(Unqual!(ForeachType!(T))==char)){
			serializeCustomVectorString!(load)(var, con);
		}else{
			alias ElementType=Unqual!(ForeachType!(T));
			uint dataLength=cast(uint)(var.length);
			serializeCharToken!(load)('[',con);
			
			static if(load==Load.yes){
				static if(hasMember!(T,"initialize")){
					var.initialize();
				}
				
				while(!con[0].isChar(']')){
					ElementType element;
					serializeImpl!(load)(element,con);
					var~=element;
					if(con[0].isChar(',')){
						serializeCharToken!(load)(',',con);
					}else{
						break;
					}
				}
				
			}else{
				foreach(i,ref d;var){
					serializeImpl!(load)(d,con);
					if(i!=var.length-1){
						serializeCharToken!(load)(',',con);
					}
				}
				
			}
			serializeCharToken!(load)(']',con);			
		}
	}
	
	
	void serializePointer(Load load,bool useMalloc, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		commonSerializePointer!(load,useMalloc)(this,var,con);		
	}
	
	//-----------------------------------------
	//--- Helper methods for basic methods
	//-----------------------------------------
	
	
	void loadClassOrStruct(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(load==Load.yes && (is(T==class) || is(T==struct)) );
		
		while(true){
			string varNa;
			serializeName!(load)(varNa,con);
			//scope(exit)Mallocator.instance.dispose(cast(string)varNa);
			bool loaded=false;
			foreach (i, ref a; var.tupleof) {
				alias TP = AliasSeq!(__traits(getAttributes, var.tupleof[i]));
				enum bool doSerialize=!hasNoserializeUda!(TP);
				enum bool useMalloc=hasMallocUda!(TP);
				enum string varName =__traits(identifier, var.tupleof[i]);
				static if(doSerialize){
					if(varName==varNa){
						try{
							auto tmpCon=con;
							scope(failure)con=tmpCon;//revert slice
							serializeImpl!(load,useMalloc)(a,con);
							loaded=true;
							break;
						}catch(Exception e){}
					}
				}
				
			}
			if(!loaded){
				ignoreToMatchingComma!(load)(con);
			}
			
			if(con[0].isChar(',')){
				con=con[1..$];
			}else{
				break;
			}
			
			
			
		}
	}
	
	
	void saveClassOrStruct(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(load==Load.no && (is(T==class) || is(T==struct)) );
		foreach (i, ref a; var.tupleof) {
			alias TP = AliasSeq!(__traits(getAttributes, var.tupleof[i]));
			enum bool doSerialize=!hasNoserializeUda!(TP);
			enum bool useMalloc=hasMallocUda!(TP);
			enum string varNameTmp =__traits(identifier, var.tupleof[i]);
			string varName=cast(string)varNameTmp;
			serializeName!(load)(varName,con);
			serializeImpl!(load,useMalloc)(a,con);
			
			if(i!=var.tupleof.length-1){
				serializeCharToken!(load)(',' ,con);
			}
		}
	}

	
	
	void serializeName(Load load,  ContainerOrSlice)(ref string name,ref ContainerOrSlice con){
		
		static if (load == Load.yes) {
			assert(con[0].type==StandardTokens.identifier);
			name=con[0].str;
			con=con[1..$];
		} else {
			TokenData token;
			token=name;
			token.type=StandardTokens.identifier;
			con ~= token;
		}
		serializeCharToken!(load)('=' ,con);
	}

	

	

	

	

	

	
	

}





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
	Vector!char vv;
	tokensToCharVectorPreatyPrint(tokens[], vv);

	writeln(vv[]);
	
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
