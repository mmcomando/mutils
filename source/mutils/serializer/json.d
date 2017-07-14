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

/// Struct to let BoundsChecking Without GC
private struct NoGcSlice(T){
	shared static immutable Exception e=new Exception("BoundsChecking NoGcException");
	T slice;
	alias slice this;
	T opSlice(X,Y)(X start, Y end){
		if(start>=slice.length || end>slice.length){
			//assert(0);
			throw e;
		}
		return slice[start..end];
	}
	size_t opDollar() { return slice.length; }
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
			(load==Load.yes && is(ForeachType!(ContainerOrSlice)==char)) ||
			(load==Load.no  && !isDynamicArray!ContainerOrSlice)
			);
		static assert(load!=Load.skip,"Skip not supported");
		
		serializeStripLeft!(load)(con);
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
				var = con.parse!T;//TODO parse thorows GC exception
			} else {
				string str=var.to!string;
				con ~= cast(char[])str[];
			}
		}
	}

	void serializeStruct(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(is(T == struct));

		serializeStripLeft!(load)(con);
		serializeConstString!(load,"{")(con);
		serializeConstStringOptional!(load,"\n")(con);
		level++;
		static if(load==Load.yes){
			loadClassOrStruct!(load)(var,con);	
		}else{
			saveClassOrStruct!(load)(var,con);
		}
		level--;
		serializeConstStringOptional!(load,"\n")(con);
		serializeSpaces!(load)(con, level);
		serializeStripLeft!(load)(con);
		serializeConstString!(load,"}")(con);
		
	}

	
	void serializeClass(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(is(T==class));
		
		serializeStripLeft!(load)(con);
		serializeConstString!(load,"{")(con);
		serializeConstStringOptional!(load,"\n")(con);
		level++;
		static if(load==Load.yes){
			var=Mallocator.instance.make!(T);
			loadClassOrStruct!(load)(var,con);		
		}else{
			if(var is null){
				//serializeConstString!(load,"{}")(con);
			}else{
				saveClassOrStruct!(load)(var,con);
			}
		}
		level--;
		serializeConstStringOptional!(load,"\n")(con);
		serializeSpaces!(load)(con, level);
		serializeStripLeft!(load)(con);
		serializeConstString!(load,"}")(con);
		
	}

	
	void serializeStaticArray(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(isStaticArray!T);
		serializeStripLeft!(load)(con);
		serializeConstString!(load,"[")(con);
		foreach (i, ref a; var) {
			serializeImpl!(load)(a,con);
			if(i!=var.length-1){
				serializeStripLeft!(load)(con);
				serializeConstString!(load,",")(con);
				serializeConstStringOptional!(load," ")(con);
			}
		}
		serializeStripLeft!(load)(con);
		serializeConstString!(load,"]")(con);
		
	}

	
	void serializeDynamicArray(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(isDynamicArray!T);
		alias ElementType=Unqual!(ForeachType!(T));
		static if(is(ElementType==char)){
			serializeEscapedString!(load)(var, con);
			return;
		}else{		
			serializeStripLeft!(load)(con);
			serializeConstString!(load,"[")(con);
			static if(load==Load.yes){
				ElementType[] arrData=Mallocator.instance.makeArray!(ElementType)(1);
				serializeStripLeft!(load)(con);
				while(con[0]!=']'){
					serializeImpl!(load)(arrData[$-1],con);
					serializeStripLeft!(load)(con);
					if(con[0]==','){
						serializeConstString!(load,",")(con);
						serializeStripLeft!(load)(con);
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
						serializeConstString!(load,",")(con);
						serializeConstStringOptional!(load," ")(con);
					}
				}
			}

			serializeStripLeft!(load)(con);
			serializeConstString!(load,"]")(con);
		}
	}


	void serializeCustomVector(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(isCustomVector!T);
		static if(is(Unqual!(ForeachType!(T))==char)){
			serializeCustomVectorString!(load)(var, con);
		}else{
			alias ElementType=Unqual!(ForeachType!(T));
			uint dataLength=cast(uint)(var.length);
			serializeStripLeft!(load)(con);
			serializeConstString!(load,"[")(con);
			static if(load==Load.yes){
				static if(hasMember!(T,"initialize")){
					var.initialize();
				}
				while(con[0]!=']'){
					foreach(i;0..dataLength){
						ElementType element;
						serializeImpl!(load)(element,con);
						var~=element;
					}
					
					ElementType element;
					serializeImpl!(load)(element,con);
					var~=element;
					serializeStripLeft!(load)(con);
					if(con[0]==','){
						serializeConstString!(load,",")(con);
						serializeStripLeft!(load)(con);
					}else{
						break;
					}
				}
				
			}else{
				foreach(i,ref d;var){
					serializeImpl!(load)(d,con);
					if(i!=var.length-1){
						serializeConstString!(load,",")(con);
						serializeConstStringOptional!(load," ")(con);
					}
				}
			}	
			
			serializeStripLeft!(load)(con);
			serializeConstString!(load,"]")(con);
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
			string varNa;
			serializeName!(load)(varNa,con);
			scope(exit)Mallocator.instance.dispose(cast(char[])varNa);
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
			
			if(loaded==false){
				serializeStripLeft!(load)(con);
				if(con[0]=='{'){
					serializeConstString!(load,"{")(con);
					serializeIgnoreToMatchingBrace!(load)(con);
				}else{
					serializeIgnoreToCommaOrBrace!(load)(con);
				}
			}			
			
			serializeStripLeft!(load)(con);
			if(con.length && con[0]==','){
				serializeConstString!(load,",")(con);
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
			string varName =__traits(identifier, var.tupleof[i]);
			serializeName!(load)(varName,con);
			serializeImpl!(load,useMalloc)(a,con);
			
			if(i!=var.tupleof.length-1){
				serializeStripLeft!(load)(con);
				serializeConstString!(load,",")(con);
				serializeConstStringOptional!(load,"\n")(con);
			}
		}
	}

	void serializeCustomVectorString(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		alias ElementType=Unqual!(ForeachType!(T));
		static assert(isCustomVector!T);
		static assert(is(ElementType==char));

		serializeStripLeft!(load)(con);
		serializeConstString!(load,"\"")(con);
		static if(load==Load.yes){
			auto index=con[0..$].indexOf('"');
			assert(index!=-1);
			var~=con[0..index];
			con=con[index..$];
		}else{
			con~=var[];
		}
		serializeConstString!(load,"\"")(con);
	}
	
	//-----------------------------------------
	//--- Helper methods for json format
	//-----------------------------------------


	void serializeName(Load load,  ContainerOrSlice)(ref string name,ref ContainerOrSlice con){		
		serializeSpaces!(load)(con, level);
		serializeStripLeft!(load)(con);
		serializeEscapedString!(load)(name, con);
		serializeStripLeft!(load)(con);
		serializeConstString!(load,":" )(con);
	}


	void serializeIgnoreToCommaOrBrace(Load load,  ContainerOrSlice)(ref ContainerOrSlice con){
		static if(load==Load.yes){
			int arrBrace;
			foreach(i,ch;con){
				arrBrace+= ch=='[';
				arrBrace-= ch==']';
				if( (arrBrace<=0 && ch==',') || ch=='}'){
					con=con[i..$];
					return;
				}
			}
			assert(0);
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
