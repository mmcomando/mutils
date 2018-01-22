/// Module to replace std.stdio write functions to @nogc ones
module mutils.stdio;

import core.stdc.stdio: printf, fwrite, stdout;

import std.meta: aliasSeqOf;
import std.traits;

import mutils.conv;

static char[1024] gTmpStdioStrBuff;// Own buffer to be independant from mutils.conv 

/**
 * Writes string to stdout
 * Compared to std.stdio.writeln this writeln is not using GC, can print @disable this() structs, can print core.simd.vector's
 * write is not pure but we will pretend it is to enable write debug
 **/ 
void write(T...)(auto ref const T el) @trusted {
	static void writeImpl(EL)(auto ref const EL el){
		string elStr=to!(string)(el, gTmpStdioStrBuff[]);
		fwrite(elStr.ptr, 1, elStr.length, stdout);		
	}

	static auto assumePure(DG)(scope DG t)
		if (isFunctionPointer!DG || isDelegate!DG)
	{
		enum attrs = functionAttributes!DG | FunctionAttribute.pure_;
		return cast(SetFunctionAttributes!(DG, functionLinkage!DG, attrs)) t;
	}
	assumePure(   () => writeImpl(el[0])		)();
	static if(T.length>1){
		write(el[1..$]);
	}
}

/// Like write but adds new line at end
void writeln(T...)(auto ref const T el) {
	write(el, "\n");
}

/// Like writeln but adds space beetwen arguments
void writelns(T...)(auto ref const T el) {
	foreach(e; el){
		write(e, ' ');
	}
	write("\n");
}

/// Writes format to stdout changing %s to proper argument
/// Only %s is supported, it is not printf
void writefln(T...)(string format, auto ref const T el) {
	alias indices=aliasSeqOf!([0,1,2,3,4,5,6,7,8,9,10,123]);
	int lastEnd=0;
	int elementsWritten=0;
	for(int i=0; i<format.length; i++){
		char c=format[i];
		if(c!='%'){
			continue;
		}
		assert(format[i+1]=='s');// Only %s is supported
		write(format[lastEnd..i]);
		lastEnd=i+2;
	sw:switch(elementsWritten){
			foreach(elNum; indices[0..el.length]){
					case elNum:
					write(el[elNum]);
					break sw;
				}
			default:
				assert(0, "Wrong number of specifiers and parameters");
		}

		elementsWritten++;

	}
	write("\n");
}



private struct TestStruct{
	@nogc nothrow @safe pure:
	@disable this();
	@disable this(this);

	this(int i){}
	int a;
	double c;
}

// Function because we dont want to prit something during tests
private void testMutilsStdio() @nogc nothrow @safe pure{
	TestStruct w=TestStruct(3);
	writeln(true);
	writeln(false);
	write("__text__ ");
	writeln(w, " <- this is struct");
	// arrays
	int[9] arr=[1,2,3,4,5,6,7,8,9];
	writeln(arr[]);
	writeln(arr);
	// simd
	import core.simd;
	ubyte16 vec=14;
	writeln(vec);
	//  writeln spaced 	
	writelns(1,2,3,4,5,6,7,8,9);
	//  writefln
	writefln("%s <- this is something | and this is something -> %s", w, 1);
	//  writeln empty
	writeln();
}

unittest{
	//testMutilsStdio();
}

