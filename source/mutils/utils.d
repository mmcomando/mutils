module mutils.utils;
/**
 * Some random functions
 */

import std.stdio : writeln, writefln;



void printException(Exception e, int maxStack = 4) {
	writeln("Exception message: ", e.msg);
	writeln("File: ", e.file, " Line Number: ", e.line);
	writeln("Call stack:");
	foreach (i, b; e.info) {
		writeln(b, "\n");
		if (i >= maxStack)
			break;
	}
	writeln("--------------");
}

const(char)* getTmpSmallCString(string str) {
	assert(str.length<256);
	static char[256] tmpStr;
	tmpStr[0..str.length]=str[];
	tmpStr[str.length]='\0';
	return cast(const(char)*)tmpStr.ptr;
}



//for build in arrays
void removeInPlace(R, N)(ref R haystack, N index)
{
	haystack[index] = haystack[$ - 1];
	haystack=haystack[0 .. $ - 1];
}

bool removeElementInPlace(R, N)(ref R arr, N obj)
{
	foreach(i,a;arr){
		if(a==obj){
			arr.removeInPlace(i);
			return true;
		}
	}
	return false;
}

import std.traits: hasMember;
auto copy(T)(auto ref const T v){
	static if(hasMember!(T, "copy")){
		return v.copy;
	}else{
		return v;
	}
}