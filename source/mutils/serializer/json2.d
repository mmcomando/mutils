module mutils.serializer.json2;

import std.algorithm : stripLeft;
import std.conv;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.meta;
import std.stdio : writeln;
import std.string : indexOf;
import std.traits;

public import mutils.serializer.common;


void writelnTokens(TokenData[] tokens){
	writeln("--------");
	foreach(tk;tokens){
		writeln(tk);
	}
}

void tokensToString(TokenData[] tokens){
	JSONLexer lex=JSONLexer([' '],true);
	foreach(tk;tokens){
		lex.saveToken(tk);
	}
	writeln(lex.code[]);
}


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
			serializeImpl!(load,useMalloc)(var, con);
		}catch(Exception e){}
	}

	//support for rvalues during load
	void serialize(Load load,bool useMalloc=false, T, ContainerOrSlice)(ref T var,ContainerOrSlice con){
		static assert(load==Load.yes);
		serialize!(load,useMalloc)(var,con);		
	}

	
	

	
	
package:

	void serializeImpl(Load load,bool useMalloc=false, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(
			(load==Load.yes && is(ForeachType!(ContainerOrSlice)==TokenData)) ||
			(load==Load.no  && is(ForeachType!(ContainerOrSlice)==TokenData))
			);
		static assert(load!=Load.skip,"Skip not supported");
		static if(load==Load.yes){
			//writelnTokens(con);
		}
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
		static assert(0);
		
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
				var=con[0].getUnescapedString;
				con=con[1..$];
			} else {
				TokenData token;
				token=var;
				token.type=StandardTokens.string_;
				con ~= token;
			}
		}else{	
			serializeCharToken!(load)('[',con);
			static if(load==Load.yes){
				ElementType[] arrData=Mallocator.instance.makeArray!(ElementType)(1);
				while(!con[0].isChar(']')){
					serializeImpl!(load)(arrData[$-1],con);
					if(con[0].isChar(',')){
						serializeCharToken!(load)(',',con);
						Mallocator.instance.expandArray(arrData,1);
					}else{
						break;
					}
				}
				var=cast(T)arrData;
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

	
	void serializeCustomVector(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(isCustomVector!T);
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
					foreach(i;0..dataLength){
						ElementType element;
						serializeImpl!(load)(element,con);
						var~=element;
					}
					
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
	
	void serializeChar(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(is(T==char));
		serializeConstString!(load,"'")(con);
		static if (load == Load.yes) {
			var = con[0];
			con=con[1..$];
		} else {
			con ~= var;
		}	
		serializeConstString!(load,"'")(con);
	}
	
	
	void loadClassOrStruct(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(load==Load.yes && (is(T==class) || is(T==struct)) );
		
		while(true){
			char[] varNa;
			serializeName!(load)(varNa,con);
			//scope(exit)Mallocator.instance.dispose(cast(char[])varNa);
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
			string varNameTmp =__traits(identifier, var.tupleof[i]);
			char[] varName=cast(char[])varNameTmp;
			serializeName!(load)(varName,con);
			serializeImpl!(load,useMalloc)(a,con);
			
			if(i!=var.tupleof.length-1){
				serializeCharToken!(load)(',' ,con);
			}
		}
	}

	
	
	//-----------------------------------------
	//--- Helper methods for json format
	//-----------------------------------------

	
	void serializeName(Load load,  ContainerOrSlice)(ref char[] name,ref ContainerOrSlice con){

		static if (load == Load.yes) {
			assert(con[0].type==StandardTokens.string_);
			name=con[0].getUnescapedString;
			con=con[1..$];
		} else {
			TokenData token;
			token=name;
			token.type=StandardTokens.string_;
			con ~= token;
		}
		serializeCharToken!(load)(':' ,con);
	}

	void serializeCharToken(Load load, ContainerOrSlice)(char ch,ref ContainerOrSlice con){
		static if (load == Load.yes) {
			writelnTokens(con);
			assert(con[0].type==StandardTokens.character && con[0].isChar(ch));
			con=con[1..$];
		} else {
			TokenData token;
			token=ch;
			con ~= token;
		}
	}

	void ignoreBraces(Load load, ContainerOrSlice)(ref ContainerOrSlice con, char braceStart, char braceEnd){
		static assert(load==Load.yes );
		assert(con[0].isChar(braceStart));
		con=con[1..$];
		int nestageLevel=1;
		while(con.length>0){
			TokenData token=con[0];
			con=con[1..$];
			if(token.type!=StandardTokens.character){
				continue;
			}
			if(token.isChar(braceStart)){
				nestageLevel++;
			}else if(token.isChar(braceEnd)){
				nestageLevel--;
				if(nestageLevel==0){
					break;
				}
			}
		}
	}

	void ignoreToMatchingComma(Load load, ContainerOrSlice)(ref ContainerOrSlice con){
		static assert(load==Load.yes );
		int nestageLevel=0;
		//writelnTokens(con);
		//scope(exit)writelnTokens(con);
		while(con.length>0){
			TokenData token=con[0];
			if(token.type!=StandardTokens.character){
				con=con[1..$];
				continue;
			}
			if(token.isChar('[') || token.isChar('{')){
				nestageLevel++;
			}else if(token.isChar(']') || token.isChar('}')){
				nestageLevel--;
			}

			if(nestageLevel==0 && token.isChar(',')){
				break;
			}else{
				con=con[1..$];
			}
		}
	}

	

	

	
	

	//-----------------------------------------
	//--- Local variables
	//-----------------------------------------
	int level;
}



//-----------------------------------------
//--- Tests
//-----------------------------------------
import mutils.container.vector;
import mutils.serializer.lexer;
// test formating
unittest{
	string str=` 12345 `;
	int a;
	JSONLexer lex=JSONLexer(cast(char[])str,true);
	auto tokens=lex.tokenizeAll();

	
	//load
	__gshared static JSONSerializer serializer= new JSONSerializer();
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
		@("malloc") char[] c;
	}
	TestStruct test;
	JSONLexer lex=JSONLexer(cast(char[])str,true);
	auto tokens=lex.tokenizeAll();	
	
	//load
	__gshared static JSONSerializer serializer= new JSONSerializer();
	auto ttt=tokens[];
	serializer.serialize!(Load.yes)(test,ttt);
	assert(test.a==1);
	assert(test.b==145);
	assert(test.c=="asdasdas asdasdas asdasd asd");

	tokens.clear();

	serializer.serialize!(Load.no)(test,tokens);

	assert(tokens.length==13);
}




/*

 
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

 JSONLexer lex=JSONLexer(cast(char[])str,true);
 auto tokens=lex.tokenizeAll();	
 //load
 __gshared static JSONSerializer serializer= new JSONSerializer();
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
 Vector!char container;
 
 //save
 __gshared static JSONSerializer serializer= new JSONSerializer();
 serializer.serialize!(Load.no)(test,container);
 //writeln(container[]);
 
 //reset var
 test=TestStruct.init;
 
 //load
 serializer.serialize!(Load.yes)(test,container[]);
 assert(test.a==1);
 assert(test.b==2);
 assert(test.c=="asdasdasda asd asda");
 assert(test.aa.a==11);
 assert(test.aa.c==22);
 assert(test.aa.b=="xxxxx");
 }
 */
// test arrays
unittest{
	static struct TestStructB{
		@("malloc") char[] a=cast(char[])"ala";
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
	test.d~=[TestStructB(cast(char[])"asddd"),TestStructB(cast(char[])"asd12dd"),TestStructB(cast(char[])"asddaszdd")];
	test.e=32.52f;
	//Vector!char container;
	Vector!TokenData tokens;

	
	//save
	__gshared static JSONSerializer serializer= new JSONSerializer();
	serializer.serialize!(Load.no)(test,tokens);
	//tokensToString(tokens[]);
	JSONLexer lex=JSONLexer([],true);
	foreach(tk;tokens[]){
		lex.saveToken(tk);
	}
	lex.slice=lex.code[];
	tokens=lex.tokenizeAll();
	
	//reset var
	test=TestStruct.init;
	
	//load
	serializer.serialize!(Load.yes)(test,tokens[]);
	//writeln(test);
	assert(test.a==[1,2,3]);
	assert(test.b==[11,22,33]);
	assert(test.c[]==[1,2,3,4,5,6,7]);
}


/*
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
 */