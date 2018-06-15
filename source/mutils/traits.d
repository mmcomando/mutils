module mutils.traits;

import std.traits;

bool isForeachDelegateWithI(DG)() {
	return is(DG == delegate) && is(ReturnType!DG == int)
		&& Parameters!DG.length == 2 && isIntegral!(Parameters!(DG)[0]);
}

unittest {
	assert(isForeachDelegateWithI!(int delegate(int, double)));
	assert(isForeachDelegateWithI!(int delegate(int, double) @nogc nothrow));
	assert(!isForeachDelegateWithI!(int delegate(double, double)));
}

bool isForeachDelegateWithoutI(DG)() {
	return is(DG == delegate) && is(ReturnType!DG == int) && Parameters!DG.length == 1;
}

unittest {
	assert(isForeachDelegateWithoutI!(int delegate(int)));
	assert(isForeachDelegateWithoutI!(int delegate(size_t) @nogc nothrow));
	assert(!isForeachDelegateWithoutI!(void delegate(int)));
}

bool isForeachDelegateWithTypes(DG, Types...)() {
	return is(DG == delegate) && is(ReturnType!DG == int) && is(Parameters!DG == Types);
}

unittest {
	assert(isForeachDelegateWithTypes!(int delegate(int, int), int, int));
	assert(isForeachDelegateWithTypes!(int delegate(ref int, ref int), int, int));
	assert(!isForeachDelegateWithTypes!(int delegate(double), int, int));
}

auto assumeNoGC(T)(T t) if (isFunctionPointer!T || isDelegate!T) {
	enum attrs = functionAttributes!T | FunctionAttribute.nogc;
	return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs)) t;
}
