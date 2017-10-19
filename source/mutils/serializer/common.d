module mutils.serializer.common;

import std.algorithm : stripLeft;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.stdio;
import std.string : indexOf;
import std.traits;

import mutils.serializer.lexer_utils;

/// Runtime check, throws nogc exception on error
static void check(string str="Parsing Error")(bool ok){
	enum hardCheck=false;// if true assert on error else throw Exception
	static if(hardCheck){
		assert(ok,str);
	}else{
		shared static immutable Exception e=new Exception(str);
		if(!ok){
			throw e;
		}
	}
}


/// Enum to check if data is loaded or saved
enum Load {
	no,
	yes,
	skip
}

/// Checks if type have to be allocated by serializer
auto isMallocType(T)(){
	static if(isDynamicArray!T || isPointer!T || is(T==class)){
		return true;
	}else{
		return false;
	}
}

/// Checks if in user defined attributes(UDA) there is malloc string
/// "malloc" string UDA indicates that data should be allocated by serializer
auto hasMallocUda(Args...)(){
	bool hasMalloc=false;
	foreach(Arg;Args){
		static if(is(typeof(Arg)==string) && Arg=="malloc"){
			hasMalloc=true;
		}
	}
	return hasMalloc;
}

/// Checks if in user defined attributes(UDA) there is noserialize string
/// "noserialize" string UDA indicates that data should not be serialzied by serializer
auto hasNoserializeUda(Args...)(){
	bool hasMalloc=false;
	foreach(Arg;Args){
		static if(is(typeof(Arg)==string) && Arg=="noserialize"){
			hasMalloc=true;
		}
	}
	return hasMalloc;
}

/// Checks if type can be treated as vector ex. replace int[] with MyArray!int
bool isCustomVector(T)(){
	static if(is(T==struct) && hasMember!(T,"opOpAssign") && hasMember!(T,"opIndex") && hasMember!(T,"length")){
		return true;
	}else{
		return false;
	}
}
///Returns Load.yes when load is Load.yes or Load.skip
Load loadOrSkip(Load load)(){
	static if(load==Load.yes || load==Load.skip){
		return Load.yes;
	}else{
		return load;
		
	}
}

void commonSerialize(Load load,bool useMalloc=false, Serializer, T, ContainerOrSlice)(Serializer ser, ref T var,ref ContainerOrSlice con){
	static if (__traits(compiles,var.beforeSerialize!(load)(ser,con))) {
		var.beforeSerialize!(load)(ser,con);
	} 
	
	//serializeStripLeft!(load)(con);
	static if (__traits(compiles,var.customSerialize!(load)(ser,con))) {
		var.customSerialize!(load)(ser, con);
	} else static if (isBasicType!T) {
		ser.serializeBasicVar!(load)(var, con);
	}  else static if(isCustomVector!T){
		ser.serializeCustomVector!(load)(var, con);
	} else static if (is(T == struct)) {
		ser.serializeStruct!(load)(var, con);
	} else static if (isStaticArray!T) {
		ser.serializeStaticArray!(load)(var, con);
	}else static if (useMalloc && isMallocType!T) {
		static if(isDynamicArray!T){
			ser.serializeDynamicArray!(load)(var, con);
		}else static if(is(T==class)){
			ser.serializeClass!(load)(var, con);
		}else static if(isPointer!T){
			ser.serializePointer!(load,useMalloc)(var, con);
		}else{
			static assert(0);
		}
	} else static if (!useMalloc && isMallocType!T) {
		//don't save, leave default value
	}else static if (is(T==interface)) {
		//don't save, leave default value
	} else{
		static assert(0, "Type can not be serialized");
	}
	
	static if (__traits(compiles,var.afterSerialize!(load)(ser,con))) {
		var.afterSerialize!(load)(ser,con);
	}
}

/// Struct to let BoundsChecking Without GC
struct NoGcSlice(T){
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


void commonSerializePointer(Load load,bool useMalloc, Serializer, T, ContainerOrSlice)(Serializer ser, ref T var,ref ContainerOrSlice con){
	static assert(isPointer!T);
	alias PointTo=typeof(*var);
	bool exists=var !is null;
	ser.serializeImpl!(loadOrSkip!load)(exists, con);
	if(!exists){
		return;
	}
	static if(load==Load.yes){
		if(var is null)var=Mallocator.instance.make!(PointTo);
	}else static if(load==Load.skip){
		__gshared static PointTo helperObj;
		T beforeVar=var;
		if(var is null)var=&helperObj;
	}
	ser.serializeImpl!(load,useMalloc)(*var,con);
	static if(load==Load.skip){
		var=beforeVar;
	}
	
}


void writelnTokens(TokenData[] tokens){
	writeln("--------");
	foreach(tk;tokens){
		writeln(tk);
	}
}


void tokensToCharVectorPreatyPrint(Lexer,Vec)(TokenData[] tokens, ref Vec vec){
	__gshared static string spaces="                                                   ";
	int level=0;
	void addSpaces(){
		vec~=cast(char[])spaces[0..level*4];
	}                                                                       
	
	foreach(tk;tokens){
		if(tk.isChar('{')){
			Lexer.toChars(tk,vec);
			level++;
			vec~='\n';
			addSpaces();
		}else if(tk.isChar('}')){
			level--;
			vec~='\n';
			addSpaces();
			Lexer.toChars(tk,vec);
		}else if(tk.isChar(',')){
			Lexer.toChars(tk,vec);
			vec~='\n';
			addSpaces();
		}else{
			Lexer.toChars(tk,vec);			
		}
		
	}
}



//-----------------------------------------
//--- Helper methods for string format
//-----------------------------------------


void serializeCustomVectorString(Load load, T, ContainerOrSlice)(ref T var, ref ContainerOrSlice con){
	alias ElementType=Unqual!(ForeachType!(T));
	static assert(isCustomVector!T);
	static assert(is(ElementType==char));
	
	static if(load==Load.yes){
		var~=cast(char[])con[0].getUnescapedString;
		con=con[1..$];
	}else{
		TokenData token;
		token=cast(string)var[];
		token.type=StandardTokens.string_;
		con ~= token;
	}
}

void serializeCharToken(Load load, ContainerOrSlice)(char ch,ref ContainerOrSlice con){
	static if (load == Load.yes) {
		//writelnTokens(con);
		check(con[0].type==StandardTokens.character && con[0].isChar(ch));
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