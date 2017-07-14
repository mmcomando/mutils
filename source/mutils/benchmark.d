module mutils.benchmark;

import std.stdio:writeln;
import std.format:format;
import core.time;
import std.file:write;
import std.conv:to;

private alias Clock=MonoTimeImpl!(ClockType.precise);


void benchmark( alias benchTemplate, uint repeatNum, string outputFileName, alias CTP_Array,Args...)( Args arg){
	template RunAndSaveResults(){
		void runAndSaveResults(){
			long[repeatNum] resultLocal;
			foreach(___i;0..repeatNum){ 
				mixin benchTemplate;
				long start=Clock.currTime.ticks();
				test();
				long end=Clock.currTime.ticks();
				resultLocal[___i]=end-start;
			}
			results~=resultLocal;
			names~=___name;
		}
	}

	static string getCode(){
		string code;
		foreach(i,el;CTP_Array.Parameters)code~=format("foreach(___i%s,%s;CTP_Array.Parameters[%s].values)", el.name, el.name,i);
		code~="{\n";
		code~="enum ___name=format(\"";
		foreach(i,el;CTP_Array.Parameters)code~=format("%s:%%s ", el.name);
		code~="\",";
		foreach(i,el;CTP_Array.Parameters){
			static if(__traits(compiles,(el.values[0]).stringof)){
				code~=format("%s.stringof, ", el.name);
			}else{
				code~=format("___i%s, ", el.name);
			}
		}
		code~=");";
		
		code~="\nmixin RunAndSaveResults;runAndSaveResults();";
		code~="}";
		return code;
	}

	long[repeatNum][] results;
	string[] names;
	
	mixin(getCode());
	

	if(outputFileName !is null){
		string csvContent;
		csvContent~="index,";
		foreach(name;names){
			csvContent~=name~",";
		}
		csvContent~="\n";
		foreach(i;0..repeatNum){
			csvContent~=i.to!string~",";
			foreach(j;0..results.length){
				csvContent~=results[j][i].to!string~",";
			}
			csvContent~="\n";
		}
		write(outputFileName, csvContent);
	}
}



struct CP(string namep,ArgsP...){
	enum name=namep;
	alias values=ArgsP;
}
struct CPArray(ArgsP...){
	alias Parameters=ArgsP;
}


enum doNotInline="pragma(inline,false);version(LDC)pragma(LDC_never_inline);";
void doNotOptimize(Args...)(ref Args args) { asm { naked;ret; } }// function call overhead

unittest{    

	template TestMixin(){
		void test(){
			foreach( i;1..30_000_0){
				auto ret=testFunc(cast(TYPE)i);
				doNotOptimize(ret);
			}
		}
	}

	static auto mul(T)(T a){
		mixin(doNotInline);
		return a+200*a;
	}

	benchmark!(TestMixin, 1, null,//null is a file name 
		CPArray!(
			CP!("testFunc",mul),
			CP!("TYPE", int,double)
			)
		)();
	
}