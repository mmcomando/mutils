module mutils.conv;

import std.stdio;
import std.traits: Unqual, isPointer, isNumeric, EnumMembers, OriginalType;
import std.meta: NoDuplicates;

extern(C) int sscanf(scope const char* s, scope const char* format, ...) nothrow @nogc;
extern(C) int snprintf (scope char * s, size_t n, scope const char * format, ... ) nothrow @nogc;

TO to(TO, FROM)(auto ref const FROM from){
	static if( is(TO==FROM) ){
		return from;
	}else static if( is(TO==string) ){
		static if( is(FROM==enum)){
			return enum2str(from);
		}else static if( isNumeric!FROM || isPointer!FROM ){
			return num2str(from);
		}else static if( is(FROM==struct)){
			return struct2str(from);
		}else{
			static assert(0, "Type conversion not supported");
		}
	}else static if( is(FROM==string) ){
		static if( is(TO==enum)){
			return str2enum!(TO)(from);
		}else static if( isNumeric!TO || isPointer!TO ){
			return str2num!(TO)(from);
		}else static if( is(TO==struct)){
			return str2num!(TO)(from);
		}else{
			static assert(0, "Type conversion not supported");
		}
	}

}

unittest{
	// Convert to same value
	assert(10.to!int==10);
	// Convert numbers
	assert("10".to!ubyte==10);
	assert(10.to!string=="10");

	// Convert enums
	assert((TestEnum.a).to!string=="a");
	assert("a".to!TestEnum==TestEnum.a);

	// Convert structs
	TestStructA testStruct="TestStructA(10, 10)".str2struct!TestStructA;
	assert(testStruct.a==10);
	assert(testStruct.b==10);
	assert(testStruct.to!string=="TestStructA(10, 10)");
}

///////////////////////  Convert numbers

// string is valid only to next num2str usage
string num2str(FROM)(FROM from){
	static assert(isNumeric!FROM || isPointer!FROM, "num2str converts only numeric or pointer type to string");
	static char[1024] buff;
	string sp=getSpecifier!(FROM);
	char[5] format;
	format[0]='%';
	foreach(i, c; sp)format.ptr[1+i]=c;
	format.ptr[1+sp.length]='\0';
	int takesCharsNum=snprintf(buff.ptr, buff.length, format.ptr, from);
	if(takesCharsNum<buff.length){
		return cast(string)buff[0..takesCharsNum];
	}else{
		return cast(string)buff;
	}
}

unittest{
	assert(10.num2str=="10");
	assert((-10).num2str=="-10");
}

NUM str2num(NUM)(string from){
	static assert(isNumeric!NUM || isPointer!NUM, "str2num converts string to numeric or pointer type");
	if(from.length==0){
		return NUM.init;
	}
	NUM ret;
	string sp=getSpecifier!(NUM);
	char[32] format;
	format[]='K';
	format[0]='%';
	int takesCharsNum=snprintf(format.ptr+1, format.length, "%d", cast(int)from.length);
	foreach(i, c; sp)format.ptr[1+takesCharsNum+i]=c;
	format.ptr[1+takesCharsNum+sp.length]='\0';
	sscanf(from.ptr, format.ptr, &ret);
	return ret;
}

unittest{
	char[18] noEnd="123456789123456789";// Test without c string ending (\0)
	string empty;
	assert(empty.str2num!ubyte==0);
	assert("".str2num!ubyte==0);
	assert(str2num!int(cast(string)noEnd[0..2])==12);


	assert("10".str2num!ubyte==10);
	assert("10".str2num!ushort==10);
	assert("+10".str2num!uint==10);
	assert("+10".str2num!ulong==10);
	
	assert("-10".str2num!byte==-10);
	assert("-10".str2num!short==-10);
	assert("-10".str2num!int==-10);
	assert("-10".str2num!long==-10);
}

///////////////////////  Convert enums

string enum2str(T)(auto ref const T en){
	static assert( is(T==enum) , "T must be an enum");
	switch(en){
		foreach (i, e; NoDuplicates!(EnumMembers!T) ){
		case e:
			enum name = __traits(allMembers, T)[i];
			return name;
		}
		default:
			return "WrongEnum";

	}
}

unittest{
	assert(enum2str(TestEnum.a)=="a");
	assert(enum2str(TestEnum.b)=="b");
	assert(enum2str(cast(TestEnum)123)=="WrongEnum");
}


// format is very strict
T str2enum(T)(string str){
	static assert( is(T==enum) , "T must be an enum");
	T en;
	switch(str){
		foreach (i, e; NoDuplicates!(EnumMembers!T) ){
			enum name = __traits(allMembers, T)[i];
			case name:
			return e;
		}
		default:
			return cast(TestEnum)(OriginalType!T).max;// Probably invalid enum
			
	}
}

unittest{
	assert(str2enum!(TestEnum)("a")==TestEnum.a);
	assert(str2enum!(TestEnum)("b")==TestEnum.b);
	assert(str2enum!(TestEnum)("ttt")==byte.max);
}


///////////////////////  Convert structs
///// Enum are treated as numbers

private string getFormatString(T)(){
	string str;

	static if( is(T==struct) ){
		T s=void;

		str~=T.stringof~"(";
		foreach (i, ref a; s.tupleof) {
			alias Type=typeof(a);
			str~=getFormatString!Type;
			if(i!=s.tupleof.length-1){
				str~=", ";
			}
		}
		str~=")";
	}else static if( isNumeric!T || isPointer!T ){
		str~="%"~getSpecifier!T;		
	}

	return str;
}

unittest{
	enum string format=getFormatString!(TestStructB);
	assert(format=="TestStructB(TestStructA(%d, %hhu), %d, %lld, %hhd)");
}

private string[] getFullMembersNames(T,string beforeName)(string[] members){	
	static if( is(T==struct) ){
		T s=void;
		foreach (i, ref a; s.tupleof) {
			alias Type=typeof(a);
			enum string varName =__traits(identifier, s.tupleof[i]);
			enum string fullName =beforeName~"."~varName;
			static if( is(Type==struct) ){
				members=getFullMembersNames!(Type, fullName)( members);
			}else static if( isNumeric!Type || isPointer!Type ){
				members~=fullName;
			}
		}
	}	
	return members;
}

unittest{
	enum string[] fullMembersNames=getFullMembersNames!(TestStructA, "s")([]);
	assert(fullMembersNames==["s.a", "s.b"]);
}

private string generate_snprintf_call(string returnValueName, string bufferName, string formatSpecifier, string[] fullMembers){	
	import std.format;
	string str;
	str~=format("%s=snprintf(%s.ptr, %s.length, \"%s\"",returnValueName, bufferName, bufferName, formatSpecifier);
	foreach(memb; fullMembers){
		str~=", "~memb;
	}
	str~=");";
	return str;
}

unittest{
	enum string call=generate_snprintf_call("ret", "buff", "%d", ["s.a"]);
	assert(call=="ret=snprintf(buff.ptr, buff.length, \"%d\", s.a);");
}

private string generate_sscanf_call( string stringName, string formatSpecifier, string[] fullMembers){	
	import std.format;
	string str;
	str~=format("sscanf(%s.ptr, \"%s\"", stringName, formatSpecifier);
	foreach(memb; fullMembers){
		str~=", &"~memb;
	}
	str~=");";
	return str;
}

unittest{
	enum string call=generate_sscanf_call("str",  "%d", ["s.a"]);
	assert(call=="sscanf(str.ptr, \"%d\", &s.a);");
}

string struct2str(T)(auto ref const T s){
	static assert( is(T==struct) , "T must be a struct");

	enum string format=getFormatString!T;
	enum string[] fullMembersNames=getFullMembersNames!(T, "s")([]);

	static char[1024] buff;
	int takesCharsNum;
	mixin( generate_snprintf_call("takesCharsNum", "buff", format, fullMembersNames) );
	return cast(string)buff[0..takesCharsNum];
}

unittest{
	TestStructB test=TestStructB(2);
	assert(struct2str(test)=="TestStructB(TestStructA(1, 255), 2, 9223372036854775807, 50)");
}

// Format is very strict
T str2struct(T)(string str){
	static assert( is(T==struct) , "T must be a struct");
	T s=void;
	enum string format=getFormatString!T;
	enum string[] fullMembersNames=getFullMembersNames!(T, "s")([]);
	enum string sscanf_call=generate_sscanf_call("str", format, fullMembersNames);
	mixin(sscanf_call);
	return s;
}

unittest{
	string loadFrom="TestStructB(TestStructA(1, 255), 2, 9223372036854775807, 100)";
	TestStructB test=str2struct!(TestStructB)(loadFrom);
	assert(test.a==2);
	assert(test.b==9223372036854775807);
	assert(test.en==TestEnum.b);
	assert(test.c.a==1);
	assert(test.c.b==255);
}




string getSpecifier(TTT)(){
	static if( is(TTT==enum) ){
		alias T=OriginalType!TTT;
	}else{
		alias T=Unqual!TTT;
	}
	static if( is(T==float) ) return "g";
	else static if( is(T==double) ) return "lg";
	else static if( is(T==real) ) return "Lg";
	else static if( is(T==char) ) return "c";
	else static if( is(T==byte) ) return "hhd";
	else static if( is(T==ubyte) ) return "hhu";
	else static if( is(T==short) ) return "hd";
	else static if( is(T==ushort) ) return "hu";
	else static if( is(T==int) ) return "d";
	else static if( is(T==uint) ) return "u";
	else static if( is(T==long) ) return "lld";
	else static if( is(T==ulong) ) return "llu";
	else static if( isPointer!T ) return "p";
	else static assert(0, "Type conversion not supported");
}


// Used for tests

private enum TestEnum:byte{
	a=50,
	b=100,
}


private struct TestStructA{
	int a=1;
	ubyte b=ubyte.max;
}

private struct TestStructB{
	@disable this();
	
	this(int a){
		this.a=a;
	}
	TestStructA c;
	int a=3;
	long b=long.max;
	TestEnum en;
}

