module mutils.serializer.lexer_utils;

import std.stdio;
import mutils.container.ct_map;
import std.traits;
import std.algorithm:canFind;
import std.meta;



void updateLineAndCol(ref uint line,ref uint column, string oldSlice, string newSLice){
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
			if (ch==' ' || ch=='\t' || ch=='\n'  || ch=='\r' ){
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
			con~=cast(char[])token.str;
		}			
	}
}

void serializeCommentMultiline(bool load, Container)(ref TokenData token, ref Container con){
	static if(load==true){
		char[2] slst=['/','*'];
		assert(con[0..2]==slst[]);
		con=con[2..$];
		foreach(i, ch;con){
			if (ch=='*' && i!=con.length-1 && con[i+1]=='/'){
				token.str=con[0..i];
				con=con[i+2..$];
				token.type=StandardTokens.comment_multiline;
				return;
			}
		}
		token.str=con;
		con=null;
		token.type=StandardTokens.comment_multiline;
	}else{
		if(token.type==StandardTokens.comment_multiline){
			con~=cast(char[])"/*";
			con~=cast(char[])token.str;
			con~=cast(char[])"*/";
		}			
	}
}

unittest{
	string str="/*  aaa bbb ccc */";
	TokenData tk;
	serializeCommentMultiline!(true)(tk, str);
	assert(tk.str=="  aaa bbb ccc ");
}

void serializeCommentLine(bool load, Container)(ref TokenData token, ref Container con){
	static if(load==true){
		char[2] slsl=['/','/'];
		assert(con[0..2]==slsl[]);
		con=con[2..$];
		foreach(i, ch;con){
			if (ch=='\n'){
				token.str=con[0..i-1];
				con=con[i..$];
				token.type=StandardTokens.comment_line;
				return;
			}
		}
		token.str=con;
		con=null;
		token.type=StandardTokens.comment_line;
	}else{
		if(token.type==StandardTokens.comment_line){
			con~=cast(char[])"//";
			con~=cast(char[])token.str;
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
				token.str=con[1..end];
				con=con[end..$];
			}else{
				end+=1;
				token.str=con[1..end];
				con=con[end+1..$];
			}

		}
		token.type=StandardTokens.string_;
	}else{
		if(token.type==StandardTokens.string_){
			con~=token.str;
		}			
	}
}

import mutils.conv;
/// Returns string is valid only to next call to any mutils.conv function
string doubleToString(double num){
	return num.to!string;
}

/// Returns string is valid only to next call to any mutils.conv function
string longToString(long num){
	return num.to!string;
}

long stringToLong(string str){
	return str.to!long;
}

void serializeNumberToken(bool load, Container)(ref TokenData token, ref Container con){
	static if(load==true){
		bool minus=false;
		string firstPart;
		string secondPart;
		if(con[0]=='-'){
			minus=true;
			con=con[1..$];
		}
		foreach(i,ch;con){
			if( ch>='0' && ch<='9'){
				firstPart=con[0..i+1];
			}else{
				break;
			}
		}
		con=con[firstPart.length..$];
		if(con.length>0 && con[0]=='.'){
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
			token.double_=minus?-num:num;
			token.type=StandardTokens.double_;
		}else{
			long num=stringToLong(firstPart);
			token.long_=minus?-num:num;
			token.type=StandardTokens.long_;
		}
	}else{
		if(token.type==StandardTokens.double_){
			con~=cast(char[])doubleToString(token.double_);
		}else if(token.type==StandardTokens.long_){
			con~=cast(char[])longToString(token.long_);
		}else{
			assert(0);
		}
	}
}


alias whiteTokens=AliasSeq!('\n','\t','\r',' ');



import mutils.container.vector;


enum StandardTokens{
	notoken=0,
	white=1,
	character=2,
	identifier=3,
	string_=4,
	double_=5,
	long_=6,
	comment_multiline=7,
	comment_line=8,
}

struct TokenData{
	union{
		string str;
		char ch;
		long long_;
		double double_;
	}
	uint line;
	uint column;
	uint type=StandardTokens.notoken;

	char getChar(){
		assert(type==StandardTokens.character);
		return ch;
	}

	string getUnescapedString(){
		assert(type==StandardTokens.string_);
		return str;
	}

	string getEscapedString(){
		return str;
	}

	bool isChar(char ch){
		return type==StandardTokens.character && this.ch==ch;
	}
	
	bool isString(string ss){
		return (
			type==StandardTokens.comment_line ||
			type==StandardTokens.comment_multiline ||
			type==StandardTokens.identifier ||
			type==StandardTokens.string_ ||
			type==StandardTokens.white 
			) && 
			str==ss;
	}

	bool isComment(){
		return type==StandardTokens.comment_line || type==StandardTokens.comment_multiline;
	}




	void opAssign(T)(T el)
		if(isIntegral!T || isFloatingPoint!T || is(T==string) || is(Unqual!T==char)  || is(T==bool) )
	{
		alias TP=Unqual!T;
		static if(isIntegral!TP || is(T==bool)){
			type=StandardTokens.long_;
			this.long_=el;
		}else static if(isFloatingPoint!TP){
			type=StandardTokens.double_;
			this.double_=el;
		}else static if( is(TP==string) ){
			type=StandardTokens.string_;
			this.str=el;
		}else static if( is(TP==char) ){
			type=StandardTokens.character;
			this.ch=el;
		}else {
			static assert(0);
		}
	}

	bool isType(T)()
		if(isIntegral!T || isFloatingPoint!T || is(T==string) || is(T==char) || is(T==bool) )
	{
		static if(isIntegral!T || is(T==bool) ){
			return type==StandardTokens.long_;
		}else static if(isFloatingPoint!T){
			return type==StandardTokens.double_;
		}else static if( is(T==string) ){
			return type==StandardTokens.string_;
		}else static if( is(T==char) ){
			return type==StandardTokens.character;
		}else{
			static assert(0);
		}
	}

	auto get(T)()
		if(isIntegral!T || isFloatingPoint!T || is(T==string) || is(T==char) || is(T==bool) )
	{
		static if(isIntegral!T || is(T==bool)){
			assert(type==StandardTokens.long_);
			return cast(T)long_;
		}else static if(isFloatingPoint!T){
			assert(type==StandardTokens.double_);
			return cast(T)double_;
		}else static if( is(T==string) ){
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
			case StandardTokens.comment_line:
			case StandardTokens.comment_multiline:
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

alias TokenDataVector=Vector!(TokenData);


void printAllTokens(Lexer)(ref Lexer lex){
	TokenData token;
	while(token.type!=Token.notoken){
		token=lex.getNextToken();
		writeln(token);
	}
}



TokenDataVector tokenizeAll(Lexer)(ref Lexer lex){
	TokenDataVector tokens;
	do{
		tokens~=lex.getNextToken();
	}while(tokens[$-1].type!=StandardTokens.notoken);
	
	return tokens;
}



Vector!char tokensToString(Lexer)(ref Lexer lex,TokenData[] tokens){
	Vector!char code;
	foreach(tk;tokens)
		lex.toChars(tk, code);
	return code;
}