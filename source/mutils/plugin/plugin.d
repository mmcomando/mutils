module mutils.plugin.plugin;

import std.datetime : SysTime;
import std.file : timeLastModified;
import std.format : format;
import std.process : executeShell;
import std.stdio : writeln;

import mutils.plugin.load_lib;
import mutils.plugin.safe_executor;
import mutils.container.vector;

struct PluginManager{
	version(DigitalMars){
		enum compiler="dmd";
	}else{
		enum compiler="ldc";
	}
	
	Vector!string includes;
	
	alias PluginFunction=void function();
	static struct PluginData{
		string path;
		SysTime lastChange;
		SharedLibHandle lib;
		PluginFunction initialize;
		PluginFunction run;
		PluginFunction dispose;
	}
	
	PluginData[string] plugins;
	SafeExecutor queue;
	
	void initialize(){
		queue.initialize();
	}
	
	void end(){
		queue.end();
		foreach(ref plugin;plugins.byValue){
			unloadPlugin(&plugin);
		}
	}
	
	bool runPlugin(string pluginPath){
		auto plugin=loadPlugin(pluginPath);
		if(plugin is null){
			return false;
		}
		return runPlugin(plugin);
	}
	
	PluginData* loadPlugin(string pluginPath){
		PluginData* plugin;
		plugin = pluginPath in plugins;
		SysTime lastChange;
		try{
			lastChange=timeLastModified(pluginPath);
		}catch(Exception e){
			return null;
		}
		if(plugin !is null){
			if(plugin.lastChange!=lastChange){
				unloadPlugin(plugin);
				bool ok=compilePlugin(plugin);
				if(!ok)return null;
				ok=loadPluginData(plugin);
				if(!ok)return null;
				plugin.lastChange=lastChange;
			}else{
				return (plugin.run is null)?null:plugin;
			}
		}else{
			PluginData pluginData;
			pluginData.path=pluginPath;
			pluginData.lastChange=lastChange;
			bool ok=compilePlugin(&pluginData);
			if(!ok)return null;
			ok=loadPluginData(&pluginData);
			if(!ok)return null;
			plugins[pluginPath]=pluginData;
			plugin = pluginPath in plugins;//TODO double lookup
			
		}
		return plugin;
		
	}
	
	bool compilePlugin(PluginData* plugin){
		string pluginName=plugin.path~".so";
		string command;
		if(compiler=="dmd"){
			command=format("%s  %s -g -of%s  -boundscheck=on -shared -fPIC -defaultlib=libphobos2.so", compiler, plugin.path, pluginName);
		}else{
			command=format("%s  %s -g -of%s  -boundscheck=on -shared -relocation-model=pic -defaultlib=/usr/lib/libphobos2-ldc.so.73 -defaultlib=/usr/lib/libdruntime-ldc.so.73", compiler, plugin.path, pluginName);
		}
		
		foreach(string include;includes){
			command~=" -I"~include;
		}
		auto output = executeShell(command);
		if(output.status != 0){
			writeln("Error compiling plugin.");
			writeln("Output: ", output.output);
			return false;
		}
		return true;
	}
	
	static bool loadPluginData(PluginData* plugin){
		plugin.lib = LoadSharedLib(plugin.path~".so");
		if(plugin.lib is null){
			writeln("Error loading plugin: ", GetErrorStr());
			return false ;
		}
		plugin.initialize=cast(void function())GetSymbol(plugin.lib, "plugin_initialize");
		plugin.run=		  cast(void function())GetSymbol(plugin.lib, "plugin_run");
		plugin.dispose=   cast(void function())GetSymbol(plugin.lib, "plugin_dispose");
		
		if(plugin.run is null){
			writeln("Error loading plugin main function.");
			unloadPlugin(plugin);
			return false;
		}
		if(plugin.initialize !is null){
			plugin.initialize();
		}
		return true;
		
	}
	
	static void unloadPlugin(PluginData* plugin){
		if(plugin.dispose !is null){
			plugin.dispose();
		}
		if(plugin.lib !is null){
			UnloadSharedLib(plugin.lib);
		}
		plugin.initialize=null;
		plugin.run=null;
		plugin.dispose=null;
	}
	
	
	bool runPlugin(PluginData* plugin){
		if(plugin.run is null){
			return false;
		}
		return queue.execute(plugin.run);
	}
	
}

unittest{
	/*import mutils.plugin.plugin;
	immutable string include="./source";
	import core.thread;	
	
	PluginManager pluginManager;
	pluginManager.initialize();
	pluginManager.includes.add(include);
	
	string pluginPath="./dll.d";
	auto plugin=pluginManager.loadPlugin(pluginPath);
	if(plugin is null){
		writeln("Error compiling plugin");
	}else{
		pluginManager.runPlugin(plugin);
	}
	pluginManager.end();*/
	
}