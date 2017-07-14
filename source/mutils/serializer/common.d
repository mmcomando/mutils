module mutils.serializer.common;

import std.algorithm : stripLeft;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.stdio;
import std.string : indexOf;
import std.traits;

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
	} else{
		static assert(0, "Type can not be serialized");
	}
	
	static if (__traits(compiles,var.afterSerialize!(load)(ser,con))) {
		var.afterSerialize!(load)(ser,con);
	}
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

//-----------------------------------------
//--- Helper methods for string formats
//-----------------------------------------

void serializeSpaces(Load load,  ContainerOrSlice)(ref ContainerOrSlice con,uint level){
	enum spacesNum=4;
	static if(load==Load.yes){
	}else{
		foreach(i;0..level){
			foreach(j;0..spacesNum){
				con~=' ';
			}
		}
	}
}



void serializeConstString(Load load,string str,  ContainerOrSlice)(ref ContainerOrSlice con){
	static if(load==Load.yes){
		/*	writeln("-----");
			 writeln(con);
			 writeln("-");
			 writeln(str);*/
		check!("Expected: "~str)(con[0..str.length]==str);
		con=con[str.length..$];
	}else{
		con~=cast(char[])str;
	}
}
void serializeConstStringOptional(Load load,string str,  ContainerOrSlice)(ref ContainerOrSlice con){
	static if(load==Load.yes){
		if(con.length>=str.length && con[0..str.length]==str){
			con=con[str.length..$];
		}
	}else{
		con~=cast(char[])str;
	}
}
void serializeStripLeft(Load load,  ContainerOrSlice)(ref ContainerOrSlice con){
	static if(load==Load.yes){
		con=con.stripLeft!( a => a == ' ' || a=='\t' || a=='\n' || a=='\r'  );
	} 
}
void serializeIgnoreToMatchingBrace(Load load,  ContainerOrSlice)(ref ContainerOrSlice con){
	static if(load==Load.yes){
		int braceDeep;
		foreach(i,ch;con){
			braceDeep+= ch=='{';
			braceDeep-= ch=='}';
			if(braceDeep<0){
				con=con[i+1..$];
				return;
			}
		}
		assert(0);
	} 
}

/// save string with escape char
void serializeEscapedString(Load load,  ContainerOrSlice)(ref string str,ref ContainerOrSlice con){
	static if(load==Load.yes){
		loadEscapedString!(load)(str, con);
	}else{
		saveEscapedString!(load)(str, con);
	}
}
void loadEscapedString(Load load,  ContainerOrSlice)(ref string str,ref ContainerOrSlice con){
	static assert(load==Load.yes);
	check(con[0]=='"');
	size_t end;
	size_t charsNum;
	size_t wasEscape;
	foreach(i,char ch;con[1..$]){
		if(!wasEscape && ch=='"'){
			end=i+1;
			break;
		}
		if(!wasEscape){
			charsNum++;
		}
		wasEscape=ch=='\\' && !wasEscape;
		
	}
	
	char[] decoded=Mallocator.instance.makeArray!(char)(charsNum);
	size_t charNum;
	wasEscape=false;
	foreach(i,char ch;con[1..end]){
		decoded[charNum]=ch;
		
		wasEscape=ch=='\\' && !wasEscape;
		if(!wasEscape){
			charNum++;
		}
		
	}
	str=cast(string)decoded;
	con=con[end+1..$];
}
void saveEscapedString(Load load,  ContainerOrSlice)(ref string str,ref ContainerOrSlice con){
	static assert(load==Load.no);
	
	con~='"';
	foreach(char ch;str){
		if(ch=='\\' || ch=='"'){
			con~='\\';
		}
		con~=ch;
	}
	con~='"';
}



unittest{
	//JSONSerializer json=new JSONSerializer;
	string innn=`"\\\\--\"|\"\""`;
	string innnSlice=innn;
	//string in=`\\--"|""`;
	string outt;
	loadEscapedString!(Load.yes)(outt,innnSlice);
	string encoded;
	saveEscapedString!(Load.no)(outt,encoded);
	assert(innn==encoded);
}
