/**
Module with some usefull functions
*/
module mutils.job_manager.utils;

import std.traits;
import std.stdio:writefln,writeln;

// Casts @nogc out of a function or delegate type.
auto assumeNoGC(T) (T t) if (isFunctionPointer!T || isDelegate!T)
{
	enum attrs = functionAttributes!T | FunctionAttribute.nogc;
	return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs)) t;
}

void writelnng(T...)(T args){
	assumeNoGC( (T arg){writeln(arg);})(args);
}

void assertM(A,B,string file=__FILE__,uint line=__LINE__)(A a,B b){
	if(a!=b){
		writefln("File: %s:%s  A: %s, B: %s",file,line,a,b);
		assert(a==b);
	}
}



version(linux){
	import std.conv;
	import std.demangle;
	private static struct  Dl_info {
		const char *dli_fname; 
		void       *dli_fbase;  
		const char *dli_sname;  
		void       *dli_saddr; 
	}
	private extern(C) int dladdr(void *addr, Dl_info *info);
	
	string functionName(void* addr){
		Dl_info info;
		int ret=dladdr(addr,&info);
		return info.dli_sname.to!(string).demangle;
	}
}else{
	string functionName(void* addr){
		return "???";
	}
}

void printException(Exception e, int maxStack = 40) {
	writeln("Exception message: %s", e.msg);
	writefln("File: %s Line Number: %s", e.file, e.line);
	writeln("Call stack:");
	foreach (i, b; e.info) {
		writeln(b);
		if (i >= maxStack)
			break;
	}
	writeln("--------------");
}
void printStack(){
	static immutable Exception exc=new Exception("Dummy");
	try{
		throw exc;
	}catch(Exception e ){
		printException(e);
	}
}