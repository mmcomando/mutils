module mutils.container.string_tmp;

import core.stdc.stdlib;
import core.stdc.string;

static struct StringTmp {
    @disable this();
    @disable this(this);

    const(char)[] str;
    bool deleteMem;

    this(const(char)[] str, bool deleteMem) {
        this.str = str;
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
        free(cast(void*) str.ptr);
        str = null;
    }
}
