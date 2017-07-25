module mutils.serializer.lexer;

import std.stdio;
import mutils.container.ct_map;
import std.traits;
import std.algorithm:canFind;


struct Lexer(Token, Map)
{

	struct TokenData{
		string str;
		uint line;
		uint column;
		Token type;

		bool isChar(char ch){
			return type==Token.character && str[0]==ch;
		}

		bool isString(string ss){
			return str==ss;
		}
	}

	uint line;
	uint column;

	void serialize(bool load, Container)(ref TokenData token, ref Container con){
		auto sliceCopy=con[];
		static if(load==true){
			foreach(i,keyValue;Map.byKeyValue){
				//pragma(msg,keyValue);
				static if(__traits(isTemplate,keyValue.value)){
					alias func=keyValue.value;
					func!(load)(token,con);
					if(token.type!=Token.notoken)goto check_line;
				}else static if(is(typeof(keyValue.value)==string)){
					if(con.length>=keyValue.value.length && con[0..keyValue.value.length]==keyValue.value){
						token.type=keyValue.key;
						con=con[keyValue.value.length..$];
						goto check_line;
					}
				}else{
					static assert(false, "Value type not supported");
				}
			}
			con=null;
			return;

		check_line:
			token.line=line;
			token.column=column;
			foreach(char ch;sliceCopy[0..sliceCopy.length-con.length]){
				if(ch=='\n'){
					line++;
					column=0;
				}else{
					column++;
				}
			}
			return;
		}else{
			foreach(i,keyValue;Map.byKeyValue){
				//pragma(msg,keyValue);
				static if(__traits(isTemplate,keyValue.value)){
					alias func=keyValue.value;
					func!(load)(token,con);
					if(sliceCopy.length!=con.length)return;
				}else static if(is(typeof(keyValue.value)==string)){
					if(token.type==keyValue.key){
						con~=keyValue.value;
						return;
					}
				}else{
					static assert(false, "Value type not supported");
				}
			}
		}
	}
}

void whiteTokens(bool load, TokenData, Container)(ref TokenData token, ref Container con){
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
			token.type=TokenData.type.white;
			return;
			
		}
		token.type=TokenData.type.notoken;
	}else{
		if(token.type==TokenData.type.white){
			con~=token.str;
		}			
	}
}

void variableName(bool load, TokenData, Container)(ref TokenData token, ref Container con){
	static if(load==true){
		size_t charactersNum=0;
		char fch=con[0];
		if((fch>='a' && fch<='z') || (fch>='A' && fch<='Z') || fch=='_'){
			charactersNum++;
		}else{
			token.type=TokenData.type.notoken;
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
			token.type=TokenData.type.variableName;
			return;
			
		}
		token.type=TokenData.type.notoken;
	}else{
		if(token.type==TokenData.type.white){
			con~=token.str;
		}			
	}
}

void stringToken(bool load, TokenData, Container)(ref TokenData token, ref Container con){
	static if(load==true){
		char fch=con[0];
		if(fch=='"'){
			size_t end=con[1..$].indexOf('"');
			if(end==-1){
				end=con.length;
			}else{

			}
		}
		token.type=TokenData.type.notoken;
	}else{
		if(token.type==TokenData.type.white){
			con~=token.str;
		}			
	}
}


void characterTokens(bool load, TokenData, Container)(ref TokenData token, ref Container con){
	enum char[] tokens=['[',']','{','}','(',')','.',','];
	
	static if(load==true){
		if(tokens.canFind(con[0])){
			token.str=[con[0]];
			con=con[1..$];
			token.type=TokenData.type.character;
			return;
		}
		token.type=TokenData.type.notoken;
	}else{
		if(token.type==TokenData.type.character){
			con~=token.str[0];
		}			
	}
}

unittest{
	enum Token{
		notoken,
		white,
		character,
		body_=128,
		something=129,
	}







	alias tokenMap=CTMap!(
		Token.notoken,characterTokens,
		Token.notoken,whiteTokens,
		Token.body_,"body",
		Token.something,"something",
		);
	alias MyLexer=Lexer!(Token,tokenMap);
	MyLexer lexer;
	MyLexer.TokenData token;

	string code="body   something body {}[]()";
	lexer.serialize!(true)(token,code);
	writeln(token);
	lexer.serialize!(true)(token,code);
	writeln(token);
	while(code.length>0 && token.type!=Token.notoken){
		token=MyLexer.TokenData.init;
		lexer.serialize!(true)(token,code);
		writeln(token);
	}
	lexer.serialize!(false)(token,code);
	writeln(code);
}




import mutils.container.vector;

struct JSONLexer{
	enum Token{
		notoken,
		white,
		character,
		variableName,
	}

	alias tokenMap=CTMap!(
		Token.notoken,characterTokens,
		Token.notoken,whiteTokens,
		Token.variableName,variableName,
		);


	alias MyLexer=Lexer!(Token,tokenMap);
	alias TokenDataVector=Vector!(MyLexer.TokenData);
	MyLexer lexer;

	string code;
	MyLexer.TokenData lastToken;

	@disable this();

	this(string code){
		this.code=code;
	}

	bool hasNextToken(){
		return code.length>0;
	}

	auto getNextToken(){
		if(hasNextToken){
			lexer.serialize!(true)(lastToken,code);
		}
		return lastToken;
	}

	void printAllTokens(){
		MyLexer.TokenData token;
		while(code.length>0 && token.type!=Token.notoken){
			token=MyLexer.TokenData.init;
			lexer.serialize!(true)(token,code);
			writeln(token);
		}
	}

	TokenDataVector tokenizeAll(){
		TokenDataVector tokens;
		while(hasNextToken()){
			tokens~=getNextToken();
		}
		return tokens;
	}


}

unittest{
	string code="{[asdf]}";
	JSONLexer json=JSONLexer(code);
	writeln(json.tokenizeAll()[]);
}