module mutils.benchmark;

import std.stdio:writeln,File;
import core.time;
import std.file;
import std.conv:to;

private alias Clock=MonoTimeImpl!(ClockType.precise);


struct BenchmarkData(uint testsNum, uint iterationsNum){
	long[iterationsNum][testsNum] times;

	void start(size_t testNum)(size_t iterationNum){
		times[testNum][iterationNum]=Clock.currTime.ticks();
	}

	void end(size_t testNum)(size_t iterationNum){
		long end=Clock.currTime.ticks();
		times[testNum][iterationNum]=end-times[testNum][iterationNum];
	}

	void writeToCsvFile()(string outputFileName){
		string[testsNum] testNames;
		foreach(i;0..testsNum){
			testNames[i]=i.to!string;
		}
		writeToCsvFile(outputFileName, testNames);
	}

	void writeToCsvFile(string outputFileName, string[testsNum] testNames){
		float to_ms=1000.0/Clock.ticksPerSecond;
		auto f = File(outputFileName, "w");	
		scope(exit)f.close();

		f.write("index,");
		foreach(name;testNames){
			f.write(name);
			f.write(" [ms],");
		}
		f.write("\n");
		foreach(i;0..iterationsNum){
			f.write(i);
			f.write(",");
			foreach(j;0..testsNum){
				f.write(times[j][i]*to_ms);
				f.write(",");
			}
			f.write("\n");
		}
	}


	void plotUsingGnuplot(string outputFileName){
		string[testsNum] testNames;
		foreach(i;0..testsNum){
			testNames[i]=i.to!string;
		}
		plotUsingGnuplot(outputFileName, testNames);
	}

	void plotUsingGnuplot(string outputFileName, string[testsNum] testNames){
		string temDir=tempDir();
		string tmpOutputFileCsv=temDir~"/tmp_bench.csv";
		writeToCsvFile(tmpOutputFileCsv, testNames);
		scope(exit)remove(tmpOutputFileCsv);

		
		string tmpScript=temDir~"/tmp_bench.gnuplot";
		auto f = File(tmpScript, "w");	
		scope(exit)remove(tmpScript);
		f.write(gnuplotScriptParts[0]);
		f.write(outputFileName);
		f.write(gnuplotScriptParts[1]);
		f.write(tmpOutputFileCsv);
		f.write(gnuplotScriptParts[2]);
		f.close();

		import std.process;
		auto result = execute(["gnuplot", tmpScript]);
		assert(result.status == 0);
	}

	string[3] gnuplotScriptParts=[`
#
set terminal png 
set output '`,`'
set key autotitle columnhead

set key left box
set samples 50
set style data points

set datafile separator ","
#plot  using 1:2  with linespoints, 'result.csv' using 1:3  with linespoints
plot for [col=2:40] '`,`' using 1:col with linespoints`

	];

	
}

enum doNotInline="pragma(inline,false);version(LDC)pragma(LDC_never_inline);";
void doNotOptimize(Args...)(ref Args args) { asm { naked;ret; } }// function call overhead

unittest{    
	import std.meta;

	
	static auto mul(T)(T a){
		mixin(doNotInline);
		return a+200*a;
	}
	alias BenchTypes=AliasSeq!(int, double);
	enum iterationsNum=40;

	BenchmarkData!(BenchTypes.length, iterationsNum) bench;

	foreach(testNum, TYPE;BenchTypes){
		foreach( itNum; 0..iterationsNum){
			bench.start!(testNum)(itNum);
			TYPE sum=0;
			foreach( i;1..30_000_0){
				sum+=mul(cast(TYPE)i);
			}
			doNotOptimize(sum);
			bench.end!(testNum)(itNum);
		}
	}
	bench.writeToCsvFile("test.csv",["mul int", "mul double"]);
	
}