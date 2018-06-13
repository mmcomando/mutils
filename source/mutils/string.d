module mutils.string;

import core.stdc.stdlib;
import core.stdc.string;

import mutils.container.string_tmp;

auto getTmpCString(const(char)[] dstr, char[] buffer = null) {
	if (dstr.length == 0) {
		return StringTmp(cast(const(char)[]) "\0", false);
	}
	if (dstr[$ - 1] == '\0') {
		return StringTmp(cast(const(char)[]) dstr, false);
	}
	if (buffer.length >= dstr.length + 1) {
		memcpy(buffer.ptr, cast(void*) dstr.ptr, dstr.length);
		buffer[dstr.length] = '\0';
		return StringTmp(cast(const(char)[])(buffer[0 .. dstr.length + 1]), false);
	}

	char[] mem = StringTmp.allocateStr(dstr.length + 1);
	memcpy(mem.ptr, cast(void*) dstr.ptr, dstr.length);
	mem[dstr.length] = '\0';
	return StringTmp(cast(const(char)[])(mem), true);
}

unittest {
	auto tmpCString = getTmpCString("asdsdd ddd");
	assert(tmpCString.deleteMem == true);
	assert(tmpCString.str == "asdsdd ddd\0");

	tmpCString = getTmpCString("asdsdd ddd\0");
	assert(tmpCString.deleteMem == false);
	assert(tmpCString.str == "asdsdd ddd\0");

	tmpCString = getTmpCString("");
	assert(tmpCString.deleteMem == false);
	assert(tmpCString.str == "\0");
}
