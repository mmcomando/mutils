module mutils.plugin.load_lib;

alias void* SharedLibHandle;

import core.stdc.string;

char[256] charBuffer;

version(Posix) {
	import core.sys.posix.dlfcn;
	SharedLibHandle LoadSharedLib(string libName)  nothrow @nogc
	{
		assert(libName.length<charBuffer.length);
		charBuffer[libName.length]='\0';
		charBuffer[0..libName.length]=libName[0..libName.length];
		return dlopen(charBuffer.ptr, RTLD_LOCAL | RTLD_NOW);
	}
	
	void UnloadSharedLib(SharedLibHandle hlib)  nothrow @nogc
	{
		dlclose(hlib);
	}
	
	void* GetSymbol(SharedLibHandle hlib, string symbolName)  nothrow @nogc
	{
		assert(symbolName.length<charBuffer.length);
		charBuffer[symbolName.length]='\0';
		charBuffer[0..symbolName.length]=symbolName[0..symbolName.length];
		return dlsym(hlib, charBuffer.ptr);
	}
	
	string GetErrorStr() nothrow @nogc
	{
		
		char* err = dlerror();
		if(err is null)
			return null;
		
		return cast(string)err[0..strlen(err)];
	}
	
} else version(Windows){
	import core.sys.windows.windows;

	SharedLibHandle LoadSharedLib(string libName)
	{
		assert(libName.length<charBuffer.length);
		charBuffer[libName.length]='\0';
		charBuffer[0..libName.length]=libName[0..libName.length];
		return LoadLibraryA(charBuffer.ptr);
	}
	
	void UnloadSharedLib(SharedLibHandle hlib)
	{
		FreeLibrary(hlib);
	}
	
	void* GetSymbol(SharedLibHandle hlib, string symbolName)
	{
		assert(symbolName.length<charBuffer.length);
		charBuffer[symbolName.length]='\0';
		charBuffer[0..symbolName.length]=symbolName[0..symbolName.length];
		return GetProcAddress(hlib, charBuffer.ptr );
	}
	
	string GetErrorStr()
	{
		import std.windows.syserror;
		return sysErrorString(GetLastError());
	}

}else{
	static assert(false, "Platform not supported");
}