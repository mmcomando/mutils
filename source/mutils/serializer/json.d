module mutils.serializer.json;

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
		import mutils.serializer.lexer;
		import mutils.serializer.json2 : JSONSerializerToken,tokensToString,tokensToCharVectorPreatyPrint;
		try{
			static if(load==Load.yes){

				JSONLexer lex=JSONLexer(cast(string)con,true);
				auto tokens=lex.tokenizeAll();				
				//load
				__gshared static JSONSerializerToken serializer= new JSONSerializerToken();
				serializer.serialize!(Load.yes, useMalloc)(var,tokens[]);		
				tokens.clear();
			}else{
				__gshared static JSONSerializerToken serializer= new JSONSerializerToken();
				JSONLexer.TokenDataVector tokens;
				serializer.serialize!(Load.no, useMalloc)(var,tokens);
				tokensToCharVectorPreatyPrint(tokens[],con);
			}
		}catch(Exception e){}
	}

	//support for rvalues during load
	void serialize(Load load,bool useMalloc=false, T, ContainerOrSlice)(ref T var,ContainerOrSlice con){
		static assert(load==Load.yes);
		serialize!(load,useMalloc)(var,con);		
	}


}



//-----------------------------------------
//--- Tests
//-----------------------------------------
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
	__gshared static JSONSerializer serializer= new JSONSerializer();
	serializer.serialize!(Load.no)(test,container);
	writeln(container[]);
	
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
	test.a=[1,2,3];
	test.b=[11,22,33];
	test.c~=[1,2,3,4,5,6,7];
	test.d~=[TestStructB("asddd"),TestStructB("asd12dd"),TestStructB("asddaszdd")];
	test.e=32.52f;
	Vector!char container;
	
	//save
	__gshared static JSONSerializer serializer= new JSONSerializer();
	serializer.serialize!(Load.no)(test,container);
	
	//reset var
	test=TestStruct.init;
	
	//load
	serializer.serialize!(Load.yes)(test,container[]);
	//writeln(test);
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
