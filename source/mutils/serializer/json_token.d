module mutils.serializer.json_token;

import std.algorithm : stripLeft;
import std.conv;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.meta;
import std.stdio : writeln;
import std.string : indexOf;
import std.traits;

public import mutils.serializer.common;

/**
 * Serializer to save data in json tokens format
 * If serialized data have to be allocated it is not saved/loaded unless it has "malloc" UDA (@("malloc"))
 */
class JSONSerializerToken{
	/**
	 * Function loads and saves data depending on compile time variable load
	 * If useMalloc is true pointers, arrays, classes will be saved and loaded using Mallocator
	 * T is the serialized variable
	 * ContainerOrSlice is string when load==Load.yes 
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
	JSONLexer lex=JSONLexer(cast(string)str,true);
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
	JSONLexer lex=JSONLexer(cast(string)str,true);
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

	JSONLexer lex=JSONLexer(cast(string)str,true);
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
