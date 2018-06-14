module mutils.container.string_tmp;

import core.stdc.stdlib;
import core.stdc.string;

static struct StringTmp {
    @disable this();
    @disable this(this);

    const(char)[] cstr= "\0";
    const(char)[] str(){
        return cstr[0 .. $-1];
    }


    bool deleteMem;
    bool hasTrailingNull;

    this(const(char)[] str, bool deleteMem) {
        assert(str[$ - 1] == '\0');
        this.cstr = str;
        this.deleteMem = deleteMem;
    }

    size_t length() {
        return str.length;
    }

    static char[] allocateStr(size_t size) {
        char* mem = cast(char*) malloc(size);
        return mem[0 .. size];
    }

    ~this() {
        if (!deleteMem) {
            return;
        }
        free(cast(void*) cstr.ptr);
        cstr = "\0";
    }
}
