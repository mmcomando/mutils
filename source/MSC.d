/// mutils shortcuts - module to make some types have shorter name

module MSC;

import mutils.container.vector;

/// Container for serializers - with shorter name, stacktrace is much more readable
struct CON_UB {
    Vector!ubyte ccc;
    alias ccc this;

    void opAssign(X)(X[] slice) {
        ccc.opAssign(slice);
    }
}

/// Container for serializers - with shorter name, stacktrace is much more readable
struct CON_C {
    Vector!char ccc;
    alias ccc this;

    void opAssign(X)(X[] slice) {
        ccc.opAssign(slice);
    }
}
