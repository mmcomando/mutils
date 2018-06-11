module mutils.string;

import core.stdc.stdlib;
import core.stdc.string;

auto getTmpCString(const(char)[] dstr, char[] buffer=null){
	static struct CStrTmp{
		@disable this();
		@disable this(this);

		const(char)[] str;
		private bool deleteMem;

		this(const(char)[] str, bool deleteMem){
			this.str=str;
			this.deleteMem=deleteMem;
		}

		~this(){
			if(!deleteMem){
				return;
			}
			free(cast(void*)str.ptr);
			str=null;
		}
	}
	if(dstr.length==0){
		return CStrTmp(cast(const(char)[])"\0", false);
	}
	if(dstr[$-1]=='\0'){
		return CStrTmp(cast(const(char)[])dstr, false);
	}
	if(buffer.length>=dstr.length+1){
		memcpy(buffer.ptr, cast(void*)dstr.ptr, dstr.length);
		buffer[dstr.length]='\0';
		return CStrTmp(cast(const(char)[])(buffer[0..dstr.length+1]), false);
	}

	char* mem=cast(char*)malloc(dstr.length+1);
	memcpy(mem, cast(void*)dstr.ptr, dstr.length);
	mem[dstr.length]='\0';
	return CStrTmp(cast(const(char)[])(mem[0..dstr.length+1]), true);
}

unittest{
	auto tmpCString=getTmpCString("asdsdd ddd");
	assert(tmpCString.deleteMem==true);
	assert(tmpCString.str=="asdsdd ddd\0");

	tmpCString=getTmpCString("asdsdd ddd\0");
	assert(tmpCString.deleteMem==false);
	assert(tmpCString.str=="asdsdd ddd\0");

	tmpCString=getTmpCString("");
	assert(tmpCString.deleteMem==false);
	assert(tmpCString.str=="\0");
}