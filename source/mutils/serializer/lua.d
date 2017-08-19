module mutils.serializer.lua;

import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.meta;
import std.traits;
import std.conv;
import std.algorithm:stripLeft;
import std.string:indexOf;
import std.stdio : writeln;

public import mutils.serializer.common;
import mutils.serializer.lua_token : LuaSerializerToken, LuaLexer;


/**
 * Serializer to save data in lua format
 * If serialized data have to be allocated it is not saved/loaded unless it has "malloc" UDA (@("malloc"))
 */
class LuaSerializer{
	/**
	 * Function loads and saves data depending on compile time variable load
	 * If useMalloc is true pointers, arrays, classes will be saved and loaded using Mallocator
	 * T is the serialized variable
	 * ContainerOrSlice is char[] when load==Load.yes 
	 * ContainerOrSlice container supplied by user in which data is stored when load==Load.no(save) 
	 */
	void serialize(Load load,bool useMalloc=false, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		import mutils.serializer.lexer;
		try{
			static if(load==Load.yes){
				
				LuaLexer lex=LuaLexer(cast(string)con, true, true);
				auto tokens=lex.tokenizeAll();				
				//load
				__gshared static LuaSerializerToken serializer= new LuaSerializerToken();
				serializer.serialize!(Load.yes, useMalloc)(var,tokens[]);		
				tokens.clear();
			}else{
				__gshared static LuaSerializerToken serializer= new LuaSerializerToken();
				TokenDataVector tokens;
				serializer.serialize!(Load.no, useMalloc)(var,tokens);
				tokensToCharVectorPreatyPrint!(LuaLexer)(tokens[],con);
			}
		}catch(Exception e){}
	}
	
	//support for rvalues during load
	void serialize(Load load,bool useMalloc=false, T, ContainerOrSlice)(ref T var,ContainerOrSlice con){
		static assert(load==Load.yes);
		serialize!(load,useMalloc)(var,con);		
	}

	__gshared static LuaSerializer instance= new LuaSerializer();

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
			Vector!char name;
			Vector!char path;
			Vector!char texPath;
			int ccc;
		}
		
		Vector!Project projects;
	}
	TestStruct test;
	TestStruct.Project p1,p2;
	p1.name~=[];
	p1.path~=['a', 'a', 'a', ' ', 'a', 'a', 'a'];
	p1.texPath~=[];
	p1.ccc=100;

	p2.name~=['d', 'd', 'd'];
	p2.path~=['c', 'c', 'c'];
	p2.texPath~=[];
	p2.ccc=200;
	test.projects~=p1;
	test.projects~=p2;
	Vector!char container;
	
	//save
	__gshared static LuaSerializer serializer= new LuaSerializer();
	serializer.serialize!(Load.no)(test,container);
	//writeln(container[]);
	
	//reset var
	test=TestStruct.init;
	
	//load
	serializer.serialize!(Load.yes)(test,container[]);
	assert(test.projects.length==2);
	assert(test.projects[0].name[]=="");
	assert(test.projects[0].path[]=="aaa aaa");
	assert(test.projects[0].ccc==100);
	
	assert(test.projects[1].name[]=="ddd");
	assert(test.projects[1].path[]=="ccc");
	assert(test.projects[1].ccc==200);
}

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
    b   =145    ,  a=  1,   c               =  


"asdasdas asdasdas asdasd asd"
}
`;
	
	
	//load
	LuaSerializer.instance.serialize!(Load.yes)(test,cast(char[])str);
	//writeln(test);
	assert(test.a==1);
	assert(test.b==145);
	assert(test.c=="asdasdas asdasdas asdasd asd");
}