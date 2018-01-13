module mutils.benchmark;

import std.stdio: writeln, writefln, File;
import std.format: format;
import core.time;
import core.sys.posix.sys.time;
import std.file;
import std.conv:to;

enum doNotInline="pragma(inline,false);version(LDC)pragma(LDC_never_inline);";
void doNotOptimize(Args...)(ref Args args) { asm { naked;ret; } }// function call overhead

private alias Clock=MonoTimeImpl!(ClockType.precise);

struct BenchmarkData(uint testsNum, uint iterationsNum){
	long[iterationsNum][testsNum] times;

	void setTime(size_t testNum)(size_t iterationNum, size_t time){
		times[testNum][iterationNum]=time;
	}

	void start(size_t testNum)(size_t iterationNum){
		times[testNum][iterationNum]=Clock.currTime.ticks();
	}

	void end(size_t testNum)(size_t iterationNum){
		long end=Clock.currTime.ticks();
		times[testNum][iterationNum]=end-times[testNum][iterationNum];
	}

	void writeToCsvFile()(string outputFileName){
		writeToCsvFile(outputFileName, defaultTestNames[0..testsNum]);
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
		plotUsingGnuplot(outputFileName, defaultTestNames[0..testsNum]);
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

	static string[10] defaultTestNames=[
		"1","2","3","4","5","6","7","8","9","10",
	];

	
}


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
	//bench.writeToCsvFile("test.csv",["mul int", "mul double"]);
	//bench.plotUsingGnuplot("test.csv",["mul int", "mul double"]);
	
}

import mutils.container.vector;
import mutils.container.buckets_chain;

static BucketsChain!(PerfData, 64, false) perfDataAlloc;
struct PerfData{
	Vector!(PerfData*) perfs;
	string funcName;
	long totalTime;
	int calls;

	float totalTimeToFloat(){
		return cast(float)totalTime/Clock.ticksPerSecond();
	}

	void reset(){
		totalTime=0;
		calls=0;
		foreach(ref p; perfs){
			p.reset();
		}
	}

	PerfData* getPerfData(string funcName){
		foreach(ref p; perfs){
			if(p.funcName==funcName){
				return p;
			}
		}
		PerfData* p=perfDataAlloc.add();
		p.funcName=funcName;
		perfs~=p;
		return p;
	}
	static int lvl=-1;
	string toString()
	{
		lvl++;
		string str;
		str~=format("%s%s \n", lvl, funcName);
		str~=format("%s%s %s %.*s \n", lvl, totalTime, calls, cast(long)(totalTime/10000000), "###################################################################");
		foreach(p; perfs){
			str~=p.toString();
		}
		lvl--;
		return str;
	}
}
/// Can be used only once in function
/// Always use: auto timeThis=TimeThis.time(); alone TimeThis.time(); is not working
struct TimeThis{

	static PerfData timingRoot;
	static PerfData* currentTiming;
	static bool enableTiming=true;

	string funcName;
	PerfData* timingMyRoot;
	long timeStart;

	static void initializeStatic(){
		currentTiming=&timingRoot;
	}

	@disable this();
	this(string funcName, long time){
		if(!enableTiming){
			return;
		}
		this.funcName=funcName;
		timeStart=time;
		timingMyRoot=currentTiming;
		currentTiming=timingMyRoot.getPerfData(funcName);
	}

	~this(){
		if(!enableTiming){
			return;
		}
		long timeEnd=Clock.currTime.ticks();
		long dt=timeEnd-timeStart;

		currentTiming.totalTime+=dt;
		currentTiming.calls+=1;
		currentTiming=timingMyRoot;
	}

	

	static TimeThis time(string funcName=__FUNCTION__){
		return TimeThis(funcName, Clock.currTime.ticks());
	}

	static void print(){
		foreach(p; timingRoot.perfs){
			writeln(*p);
		}
	}

	static PerfData*[] getRootPerfs(){
		return timingRoot.perfs[];
	}

	static void reset(){
		foreach(p; timingRoot.perfs){
			p.reset();
		}
	}

	static void enable(bool yes){
		enableTiming=yes;
	}

	

}

unittest{	
	mixin(checkVectorAllocations);
	void testA(){
		auto timeThis=TimeThis.time();
	}
	void testB(){
		auto timeThis=TimeThis.time();
	}
	{
		TimeThis.initializeStatic();
		auto timeThis=TimeThis.time();
		testA();
		testB();
	}
	perfDataAlloc.clear();
	TimeThis.timingRoot.perfs.clear();
	//TimeThis.print();
}

// Replacement for deprecated std.datetime StopWatch, used mainly in benchmark tests
struct StopWatch{
	long begin;
	long end;

	long getTime() // in us
	{
		timeval t;
		
		gettimeofday(&t, null);
		
		return t.tv_sec * 1000_000 + t.tv_usec ;
	}

	void start(){


		begin=getTime();
	}

	void stop(){
		end=getTime();
	}

	long secs(){
		return (end-begin)/1000_000;
	}

	long msecs(){
		long endTime=(end==0)?getTime:end;
		return (endTime-begin)/1000;
	}

	long usecs(){
		long endTime=(end==0)?getTime:end;
		return (endTime-begin);
	}

}