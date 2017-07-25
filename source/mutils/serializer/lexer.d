module mutils.serializer.lexer;

import std.stdio;
import mutils.container.ct_map;
import std.traits;
import std.algorithm:canFind;
import std.meta;



void updateLineAndCol(ref uint line,ref uint column, char[] oldSlice, char[] newSLice){
	foreach(char ch;oldSlice[0..oldSlice.length-newSLice.length]){
		if(ch=='\n'){
			line++;
			column=0;
		}else{
			column++;
		}
	}
}

void serializeWhiteTokens(bool load, Container)(ref TokenData token, ref Container con){
	static if(load==true){
		size_t whiteNum=0;
		foreach(ch;con){
			if (ch==' ' || ch=='\t' ||ch=='\n' ){
				whiteNum++;
			}else{
				break;
			}
		}
		if(whiteNum>0){
			token.str=con[0..whiteNum];
			con=con[whiteNum..$];
			token.type=StandardTokens.white;
			return;
			
		}
		token.type=StandardTokens.notoken;
	}else{
		if(token.type==StandardTokens.white){
			con~=token.str;
		}			
	}
}

bool isIdentifierFirstChar(char ch){
	return (ch>='a' && ch<='z') || (ch>='A' && ch<='Z') || ch=='_';
}

void serializeIdentifier(bool load, Container)(ref TokenData token, ref Container con){
	static if(load==true){
		size_t charactersNum=0;
		char fch=con[0];
		if(isIdentifierFirstChar(con[0])){
			charactersNum++;
		}else{
			token.type=StandardTokens.notoken;
			return;
		}
		foreach(ch;con[1..$]){
			if ( (ch>='a' && ch<='z') || (ch>='A' && ch<='Z') || (ch>='0' && ch<='9') || ch=='_'){
				charactersNum++;
			}else{
				break;
			}
		}
		if(charactersNum>0){
			token.str=con[0..charactersNum];
			con=con[charactersNum..$];
			token.type=StandardTokens.identifier;
			return;
			
		}
		token.type=StandardTokens.notoken;
	}else{
		if(token.type==StandardTokens.white){
			con~=token.str;
		}			
	}
}

void serializeStringToken(bool load, Container)(ref TokenData token, ref Container con){
	import std.string;
	static if(load==true){
		char fch=con[0];
		if(fch=='"'){
			size_t end=con[1..$].indexOf('"');
			if(end==-1){
				end=con.length;
			}else{
				end+=2;
			}
			token.str=con[0..end];
			con=con[end..$];

		}
		token.type=StandardTokens.string_;
	}else{
		if(token.type==StandardTokens.string_){
			con~=token.str;
		}			
	}
}

long stringToLong(char[] str){
	long num;
	long mul=1;
	foreach_reverse(ch;str){
		long numCh=ch-'0';
		num+=numCh*mul;
		mul*=10;
	}
	return num;
}

unittest{
	assert(stringToLong(cast(char[])"123")==123);
	assert(stringToLong(cast(char[])"0")==0);
}

void serializeNumberToken(bool load, Container)(ref TokenData token, ref Container con){
	static if(load==true){
		bool minus=false;
		char[] firstPart;
		char[] secondPart;
		if(con[0]=='-'){
			minus=true;
			con=con[1..$];
		}
		foreach(i,ch;con){
			if(ch>='0' && ch<='9'){
				firstPart=con[0..i+1];
			}else{
				break;
			}
		}
		con=con[firstPart.length..$];
		if(con[0]=='.'){
			con=con[1..$];
			foreach(i,ch;con){
				if(ch>='0' && ch<='9'){
					secondPart=con[0..i+1];
				}else{
					break;
				}
			}
			con=con[secondPart.length..$];
			if(con[0]=='f'){
				con=con[1..$];
			}
			double num=stringToLong(firstPart)+cast(double)stringToLong(secondPart)/(10^^secondPart.length);
			token.double_=num;
			token.type=StandardTokens.double_;
		}else{
			long num=stringToLong(firstPart);
			token.long_=num;
			token.type=StandardTokens.long_;
		}
	}else{
		if(token.type==StandardTokens.double_){
			con~=cast(char[])"1111.11111f";
		}else if(token.type==StandardTokens.long_){
			con~=cast(char[])"111111111";
		}else{
			assert(0);
		}
	}
}


alias whiteTokens=AliasSeq!('\n','\t',' ');



import mutils.container.vector;


enum StandardTokens{
	notoken=0,
	white=1,
	character=2,
	identifier=3,
	string_=4,
	double_=5,
	long_=6,
}

struct TokenData{
	union{
		char[] str;
		char ch;
		long long_;
		double double_;
	}
	uint line;
	uint column;
	uint type;

	char getChar(){
		assert(type==StandardTokens.character);
		return ch;
	}

	char[] getUnescapedString(){
		assert(type==StandardTokens.string_);
		return str[1..$-1];
	}

	char[] getEscapedString(){
		return '"'~str~'"';
	}

	bool isChar(char ch){
		return type==StandardTokens.character && this.ch==ch;
	}

	bool isString(string ss){
		return str==ss;
	}




	void opAssign(T)(T el)
		if(isIntegral!T || isFloatingPoint!T || is(T==char[]) || is(T==char))
	{
		static if(isIntegral!T){
			type=StandardTokens.long_;
			this.long_=el;
		}else static if(isFloatingPoint!T){
			type=StandardTokens.double_;
			this.double_=el;
		}else static if( is(T==char[]) ){
			type=StandardTokens.string_;
			this.str=el;
		}else static if( is(T==char) ){
			type=StandardTokens.character;
			this.ch=el;
		}else {
			static assert(0);
		}
	}
	auto get(T)()
		if(isIntegral!T || isFloatingPoint!T || is(T==char[]) || is(T==char))
	{
		static if(isIntegral!T){
			assert(type==StandardTokens.long_);
			return cast(T)long_;
		}else static if(isFloatingPoint!T){
			assert(type==StandardTokens.double_);
			return cast(T)double_;
		}else static if( is(T==char[]) ){
			assert(type==StandardTokens.string_);
			return cast(T)str;
		}else static if( is(T==char) ){
			assert(type==StandardTokens.character);
			return cast(T)ch;
		}else {
			static assert(0);
		}
	}


	string toString(){
		import std.format;
		switch(type){
			case StandardTokens.character:
				return format("TK(%5s, '%s', %s, %s)",cast(StandardTokens)type,ch,line,column);
			case StandardTokens.string_:
			case StandardTokens.identifier:
			case StandardTokens.white:
				return format("TK(%5s, \"%s\", %s, %s)",cast(StandardTokens)type,str,line,column);
			case StandardTokens.double_:
				return format("TK(%5s, %s, %s, %s)",cast(StandardTokens)type,double_,line,column);
			case StandardTokens.long_:
				return format("TK(%5s, %s, %s, %s)",cast(StandardTokens)type,long_,line,column);
			default:
				return format("TK(%5s, ???, %s, %s)",cast(StandardTokens)type,line,column);


		}
	}
}

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

	

	
	bool skipUnnecessaryWhiteTokens=true;
	Vector!char code;
	char[] slice;
	TokenData lastToken;
	uint line;
	uint column;
	alias TokenDataVector=Vector!(TokenData);
	alias characterTokens=AliasSeq!('[',']','{','}','(',')',',',':');
	
	@disable this();
	
	this(char[] code, bool skipWhite){
		this.code~=code;
		slice=this.code[];
		skipUnnecessaryWhiteTokens=skipWhite;
	}


	TokenData checkNextToken(){
		auto sliceCopy=slice;
		auto token=getNextToken();
		slice=sliceCopy;
		return token;
	}

	TokenData getNextToken(){
		char[] sliceCopy=slice[];
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
		if(token.type==Token.white){
			return getNextToken();
		}
		//writeln(slice);
		return token;
	}

	void saveToken(TokenData token){
		final switch(cast(Token)token.type){
			case Token.long_:
			case Token.double_:
				serializeNumberToken!(false)(token,code);
				break;
			case Token.character:
				code~=token.ch;
				break;
			case Token.white:
			case Token.identifier:
				code~=token.str;
				break;
			case Token.string_:
				code~=token.getEscapedString();
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
	

}

unittest{
	//writeln("--------");
	char[] code=cast(char[])`{ [ ala: "asdasd", ccc:123.3f]}"`;
	JSONLexer json=JSONLexer(code,true);
	//writeln(json.tokenizeAll()[]);
	TokenData token;
	token.type=StandardTokens.identifier;
	token.str=cast(char[])"asd";
	json.saveToken(token);
}
