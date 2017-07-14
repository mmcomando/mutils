module mutils.safe_union;

import std.algorithm : max;
import std.conv : to;
import std.meta : staticIndexOf;
import std.traits : isArray,ForeachType,hasMember,ReturnType,Parameters;

/**
 * Union of ConTypes... 
 * Ensures correct access with assert
 */
struct SafeUnion(ConTypes...) {
	alias FromTypes=ConTypes;
	static assert(FromTypes.length>0,"Union has to have members.");

	mixin(getCode!(FromTypes));
	//enum Types{...}    //from mixin
	alias Types=TypesM;// alias used to give better autocompletion in IDE-s
	Types currentType=Types.none;

	/**
	 * Constuctor supporting direcs assigment of Type
	 */
	this(T)(T obj){
		static assert(properType!T,"Given Type is not present in union");
		set(obj);
	}  
	void opAssign(SafeUnion!(ConTypes) obj){
		this.tupleof=obj.tupleof;
	}
	//void opAssign(this);
	void opAssign(T)(T obj){
		static assert(properType!T,"Given Type is not present in union");
		set(obj);
	}

	/**
	 * returns given type with check
	 */
	@nogc nothrow auto get(T)(){
		static assert(properType!T,"Given Type is not present in union");
		foreach(i,Type;FromTypes){
			static if(is(Type==T)){
				assert(currentType==i,"Got type which is not currently bound.");
				mixin("return &_"~i.to!string~";");
			}
		}
		assert(false);
	}

	/**
	 * Returns enum value for Type
	 */
	@nogc nothrow bool isType(T)(){
		static assert(properType!T,"Given Type is not present in union");
		bool ok=false;
		foreach(i,Type;FromTypes){
			static if(is(Type==T)){
				Types type=cast(Types)i;
				if(currentType==type){
					ok=true;
				}
			}
		}
		return ok;
	}

	/**
	 * Returns enum value for Type
	 */
	static Types getEnum(T)(){
		static assert(properType!T,"Given Type is not present in union");
		foreach(i,Type;FromTypes){
			static if(is(Type==T)){
				return cast(Types)i;
			}
		}
	}

	/**
	 * Sets given Type
	 */
	@nogc nothrow auto  set(T)(T obj){
		static assert(properType!T,"Given Type is not present in union");
		foreach(i,Type;FromTypes){
			static if(is(Type==T)){
				currentType=cast(Types)i;
				mixin("_"~i.to!string~"=obj;");
			}
		}
	}
	
	auto ref apply(alias fun)() {
		switch(currentType){
			mixin(getCaseCode("return fun(_%1$s);")); 			
			
			default:
				assert(0);
		}
	}



	import mutils.serializer.binary;
	/**
	 * Support for serialization
	 */
	void customSerialize(Load load, Serializer, ContainerOrSlice)(Serializer serializer,ref ContainerOrSlice con){
		serializer.serialize!(load)(currentType,con);
		final switch(currentType){
			mixin(getCaseCode("serializer.serialize!(load)(_%1$s,con);break;")); 
			case Types.none:
				break;
		}
	}

	import std.range:put;
	import std.format:FormatSpec,formatValue;
	/**
	 * Preety print
	 */
	void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt)
	{
		put(sink, "SafeUnion(");
		
		final switch(currentType){
			mixin(getCaseCode("formatValue(sink, _%1$s, fmt);break;")); 
			case Types.none:
				put(sink, "none");
				break;
		}
		
		put(sink, ")");
	}

	/**
	 * Checks if opDispatch supports given function
	 */
	static bool checkOpDispach(string funcName)(){
		bool ok=true;	
		foreach(Type;FromTypes){
			ok=ok && hasMember!(Type, funcName);
		}
		return ok;
	}  

	/**
	 * Forwards call to union member
	 * Works only if all union members has this function and this function has the same return type and parameter types
	 */
	auto opDispatch(string funcName, Args...)(Args args)
		if(checkOpDispach!(funcName)() )	
	{		
		mixin("alias CompareReturnType=ReturnType!(FromTypes[0]."~funcName~");");
		mixin("alias CompareParametersTypes=Parameters!(FromTypes[0]."~funcName~");");
		foreach(Type;FromTypes){
			mixin("enum bool typeOk=is(ReturnType!(Type."~funcName~")==CompareReturnType);");
			mixin("enum bool parametersOk=is(Parameters!(Type."~funcName~")==CompareParametersTypes);");
			static assert(typeOk,"Return type "~CompareReturnType.stringof~" of '"~funcName~"' has to be the same in every union member.");
			static assert(parametersOk,"Parameter types "~CompareParametersTypes.stringof~" of '"~funcName~"' have to be the same in every union member.");
		}
		switch(currentType){
			mixin(getCaseCode("return _%1$s."~funcName~"(args);"));
			default:
				assert(0);
		}
	}
package: 

	/** 
	 * Generates cases for switch with code, use _%1$s to place your var
	 */
	private static string getCaseCode(string code){
		string str;
		foreach(uint i,type;FromTypes){
			import std.format;
			string istr=i.to!string;
			str~="case Types._e_"~istr~":";
			str~=format(code,istr);
		}
		return str;
	}	
	
	/** 
	 * Generates enum,and union with given FromTypes
	 */
	private static string getCode(FromTypes...)(){
		string codeEnum="enum TypesM:ubyte{\n";
		string code="private union{\n";
		foreach(uint i,type;FromTypes){
			string istr=i.to!string;
			string typeName=type.stringof;
			string enumName="_e_"~istr;
			string valueName="_"~istr;
			codeEnum~=enumName~"="~istr~",\n";
			code~="FromTypes["~istr~"] "~valueName~";\n";
			
			
		}
		codeEnum~="none\n}\n";
		return codeEnum~code~"}\n";
	}

	/**
	 *  Checks if Type is in union Types
	 */
	private static  bool properType(T)(){
		return staticIndexOf!(T,FromTypes)!=-1;
	}
}
/// Example Usage
unittest{
	struct Triangle{		
		int add(int a){
			return a+10;
		}
	}
	struct Rectangle {
		int add(int a){
			return a+100;
		}
	}
	static uint strangeID(T)(T obj){
		static if(is(T==Triangle)){
			return 123;
		}else static if(is(T==Rectangle)){
			return 14342;			
		}else{
			assert(0);
		}
	}
	alias Shape=SafeUnion!(Triangle,Rectangle);
	Shape shp;
	shp.set(Triangle());
	assert(shp.isType!Triangle);
	assert(!shp.isType!Rectangle);
	assert(shp.add(6)==16);//Bad error messages if opDispatch!("add") cannot be instantiated
	assert(shp.opDispatch!("add")(6)==16);//Better error messages 
	assert(shp.apply!strangeID==123);
	//shp.get!(Rectangle);//Crash
	shp.set(Rectangle());
	assert(shp.add(6)==106);
	assert(shp.apply!strangeID==14342);
	shp.currentType=shp.Types.none;
	//shp.apply!strangeID;//Crash
	//shp.add(6);//Crash
	final switch(shp.currentType){
		case shp.getEnum!Triangle:
			break;
		case Shape.getEnum!Rectangle:
			break;
		case Shape.Types.none:
			break;
	}
}
