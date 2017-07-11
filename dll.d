import std.stdio;

import mutils.container.vector;

extern (C) void plugin_initialize()
{
	writeln("Plugin initialzie");
}

extern (C) void plugin_run()
{
	Vector!int arr;
	arr.add(1);
	arr.add(2);
	foreach(el;arr){
		write(el);
	}
	int* ww;
	writeln("Wdddasasdaddd()");
	//writeln(*ww);
	//assert(0);
}

extern (C) void plugin_dispose()
{
	writeln("Plugin dispose");
}
