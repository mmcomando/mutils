/**
Multithreated test may take some space so they are there.
 */
module mutils.job_manager.manager_tests;

import core.atomic;
import core.memory;
import core.simd;
import core.thread : Thread,ThreadID,sleep,Fiber;

import std.algorithm : sum;
import std.datetime;
import std.functional : toDelegate;
import std.random : uniform;
import std.stdio : write,writeln,writefln;

import mutils.job_manager.debug_sink;
import mutils.job_manager.manager;
import mutils.job_manager.shared_utils;
import mutils.job_manager.utils;

void makeTestJobsFrom(void function() fn,uint num){
	makeTestJobsFrom(fn.toDelegate,num);
}

void makeTestJobsFrom(JobDelegate deleg,uint num){
	UniversalJobGroup!JobDelegate group=UniversalJobGroup!JobDelegate(num);
	mixin(getStackMemory("group"));
	foreach(int i;0..num){
		group.add(deleg);
	}
	group.wait();
}

void testFiberLockingToThread(){
	ThreadID id=Thread.getThis.id;
	auto fiberData=getFiberData();
	foreach(i;0..1000){
		jobManager.addThisFiberAndYield(fiberData);
		assert(id==Thread.getThis.id);
	}
}

//returns how many jobs it have spawned
int randomRecursionJobs(int deepLevel){
	alias UD=UniversalDelegate!(int function(int));
	if(deepLevel==0){
		simpleYield();
		return 0;
	}
	int randNum=uniform(1,10);
	//randNum=10;
	
	alias ddd=typeof(&randomRecursionJobs);
	UniversalJobGroup!ddd group=UniversalJobGroup!ddd(randNum);
	mixin(getStackMemory("group"));
	foreach(int i;0..randNum){
		group.add(&randomRecursionJobs,deepLevel-1);
	}
	
	auto jobsRun=group.wait();
	return sum(jobsRun)+randNum;
}
/// One Job and one Fiber.yield
shared int myCounter;
void simpleYield(){
	auto fiberData=getFiberData();
	foreach(i;0..1){
		//DebugSink.add(atomicOp!"+="(myCounter,1));
		jobManager.addThisFiberAndYield(fiberData);
	}
}

void testPerformance(){	
	myCounter=0;
	//DebugSink.reset();	
	uint iterations=1000;
	uint packetSize=100;
	StopWatch sw;
	sw.start();
	jobManager.debugHelper.resetCounters();
	alias ddd=typeof(&simpleYield);
	UniversalJobGroup!ddd group=UniversalJobGroup!ddd(packetSize);
	mixin(getStackMemory("group"));
	foreach(int i;0..packetSize){
		group.add(&simpleYield);
	}
	//int[] pp=	new int[100];
	foreach(i;0..iterations){
		group.wait();
	}
	
	//DebugSink.verifyUnique(iterations*packetSize);
	
	assertM(jobManager.debugHelper.jobsAdded,iterations*packetSize);
	assertM(jobManager.debugHelper.jobsDone ,iterations*packetSize);
	assertM(jobManager.debugHelper.fibersAdded,iterations*packetSize+iterations);
	assertM(jobManager.debugHelper.fibersDone ,iterations*packetSize+iterations);
	sw.stop();  
	writefln( "Benchmark: %s*%s : %s[ms], %s[it/ms]",iterations,packetSize,sw.peek().msecs,iterations*packetSize/sw.peek().msecs);
}

void activeSleep(uint u_seconds){
	StopWatch sw;
	sw.start();
	while(sw.peek().usecs<u_seconds){}//for 10us will iterate ~120 tiems
	sw.stop();
	
}

void testPerformanceSleep(){	
	import std.parallelism;
	uint partsNum=1000;
	uint iterations=60;
	uint u_secs=13;
	
	
	alias ddd=typeof(&activeSleep);
	UniversalJobGroup!ddd group=UniversalJobGroup!ddd(partsNum);
	mixin(getStackMemory("group"));
	foreach(int i;0..partsNum){
		group.add(&activeSleep,u_secs);
	}
	StopWatch sw;
	sw.start();
	foreach(i;0..iterations){
		group.wait();
	}
	
	
	sw.stop();  
	result=cast(float)iterations*u_secs/sw.peek().usecs;
	
	writefln( "BenchmarkSleep: %s*%s : %s[us], %s[it/us]  %s",iterations,u_secs,sw.peek().usecs,cast(float)iterations*u_secs/sw.peek().usecs,result/base);
}





alias mat4=float[16];
//import gl3n.linalg;
void mulMat(mat4[] mA,mat4[] mB,mat4[] mC){
	assert(mA.length==mB.length && mB.length==mC.length);
	foreach(i;0..mA.length){
		foreach(k;0..1){
			mC[i]=mB[i][]*mB[i][];
		}
	}
}

__gshared float result;
__gshared float base=1;
void testPerformanceMatrix(){	
	import std.parallelism;
	uint partsNum=16;
	uint iterations=100;	
	uint matricesNum=512;
	assert(matricesNum%partsNum==0);
	mat4[] matricesA=mallocator.makeArray!mat4(matricesNum);
	mat4[] matricesB=mallocator.makeArray!mat4(matricesNum);
	mat4[] matricesC=mallocator.makeArray!mat4(matricesNum);
	scope(exit){
		mallocator.dispose(matricesA);
		mallocator.dispose(matricesB);
		mallocator.dispose(matricesC);
	}
	StopWatch sw;
	sw.start();
	jobManager.debugHelper.resetCounters();
	uint step=matricesNum/partsNum;
	
	alias ddd=typeof(&mulMat);
	UniversalJobGroup!ddd group=UniversalJobGroup!ddd(partsNum);
	mixin(getStackMemory("group"));
	foreach(int i;0..partsNum){
		group.add(&mulMat,matricesA[i*step..(i+1)*step],matricesB[i*step..(i+1)*step],matricesC[i*step..(i+1)*step]);
	}
	foreach(i;0..iterations){
		group.wait();
	}
	
	
	sw.stop();  
	result=cast(float)iterations*matricesNum/sw.peek().usecs;
	writefln( "BenchmarkMatrix: %s*%s : %s[us], %s[it/us] %s",iterations,matricesNum,sw.peek().usecs,cast(float)iterations*matricesNum/sw.peek().usecs,result/base);
}

void testForeach(){
	int[200] ints;
	shared uint sum=0;
	foreach(ref int el;ints.multithreated){
		atomicOp!"+="(sum,1);
		activeSleep(100);//simulate load for 100us
	}
	foreach(ref int el;ints.multithreated){
		activeSleep(100);
	}
	assert(sum==200);
}

void veryDummy(){
	//foreach(i;0..10)writeln("asdasd");
}

void test(uint threadsNum=16){
	
	static void startTest(){
		//callAndNothing!(typeof((&veryDummy).toDelegate))((&veryDummy).toDelegate);
		testForeach();

		alias UnDel=void delegate();
		makeTestJobsFrom(&testFiberLockingToThread,100);
		callAndWait!(UnDel)((&testPerformance).toDelegate);
		callAndWait!(UnDel)((&testPerformanceMatrix).toDelegate);
		callAndWait!(UnDel)((&testPerformanceSleep).toDelegate);
		{
			//int[] pp=	new int[1000];//Make some garbage so GC would trigger
			jobManager.debugHelper.resetCounters();
			int jobsRun=callAndWait!(typeof(&randomRecursionJobs))(&randomRecursionJobs,5);
			assert(jobManager.debugHelper.jobsAdded==jobsRun+1);
			assert(jobManager.debugHelper.jobsDone==jobsRun+1);
			assert(jobManager.debugHelper.fibersAdded==jobsRun+2);
			assert(jobManager.debugHelper.fibersDone==jobsRun+2);
		}

	}
	jobManager.startMainLoop(&startTest,threadsNum);
}
void testScalability(){
	//foreach(i;3..4){
	//	jobManager=mallocator.make!JobManager;
	//	scope(exit)mallocator.dispose(jobManager);
	//	write(i+1," ");
	test(4);
	//if(i==0)base=result;
	//}
}


unittest{
	testScalability();
}
