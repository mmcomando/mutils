/**
 Module with some usefull functions
 */
module mutils.job_manager.utils;

import std.stdio;

void assertM(A, B, string file = __FILE__, uint line = __LINE__)(A a, B b) {
	if (a != b) {
		debug writefln("File: %s:%s  A: %s, B: %s",file,line,a,b);
		assert(a == b);
	}
}

version (linux) {
	import std.conv;
	import std.demangle;
	import core.stdc.string;

	private static struct Dl_info {
		const char* dli_fname;
		void* dli_fbase;
		const char* dli_sname;
		void* dli_saddr;
	}

	private extern (C) int dladdr(void* addr, Dl_info* info);

	string functionName(void* addr) {
		Dl_info info;
		int ret = dladdr(addr, &info);
		return cast(string) info.dli_sname[0 .. strlen(info.dli_sname)];
		//return info.dli_sname.to!(string).demangle;
	}
} else {
	string functionName(void* addr) {
		return "???";
	}
}
