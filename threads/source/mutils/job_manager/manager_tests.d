﻿/**
 Multithreated test may take some space so they are there.
 */
module mutils.job_manager.manager_tests;

import core.atomic;
import core.simd;
import core.stdc.stdio;
import std.algorithm : sum;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.functional : toDelegate;

import mutils.job_manager.manager;
import mutils.job_manager.utils;
import mutils.thread : Fiber, Thread;
import mutils.time;

import std.stdio;

/// One Job and one Fiber.yield
void simpleYield() {
	auto fiberData = getFiberData();
	foreach (i; 0 .. 1) {
		jobManager.addThisFiberAndYield(fiberData);
	}
}

void simpleSleep(uint msecs) {
	if (msecs == 0) {
		return;
	}
	Thread.sleep(msecs);
}

void activeSleep(uint u_seconds) {
	StopWatch sw;
	sw.start();
	while (sw.usecs < u_seconds) {
		//writeln("kk");
	} //for 10us will iterate ~120 tiems
	sw.stop();

}

void makeTestJobsFrom(void function() fn, uint num) {
	makeTestJobsFrom(fn.toDelegate, num);
}

void makeTestJobsFrom(JobDelegate deleg, uint num) {
	UniversalJobGroup!JobDelegate group = UniversalJobGroup!JobDelegate(num);
	foreach (int i; 0 .. num) {
		group.add(deleg);
	}
	group.callAndWait();
}

void testFiberLockingToThread() {
	auto id = Thread.getThisThreadNum();
	auto fiberData = getFiberData();
	foreach (i; 0 .. 1000) {
		jobManager.addThisFiberAndYield(fiberData);
		assertKM(id == Thread.getThisThreadNum());
	}
}

//returns how many jobs it have spawned
int randomRecursionJobs(int deepLevel) {
	alias UD = UniversalDelegate!(int function(int));
	if (deepLevel == 0) {
		simpleYield();
		return 0;
	}
	int randNum = 7;

	alias ddd = typeof(&randomRecursionJobs);
	UniversalJobGroup!ddd group = UniversalJobGroup!ddd(randNum);
	foreach (int i; 0 .. randNum) {
		group.add(&randomRecursionJobs, deepLevel - 1);
	}
	auto jobsRun = group.callAndWait();
	auto sumNum=sum(jobsRun) + randNum;
	return sumNum;
}

//returns how many jobs it have spawned
void testRandomRecursionJobs() {
	jobManager.debugHelper.resetCounters();
	int jobsRun = callAndWait!(typeof(&randomRecursionJobs))(&randomRecursionJobs, 5);
	assertM(jobManager.debugHelper.jobsAdded, jobsRun + 1);
	assertM(jobManager.debugHelper.jobsDone,jobsRun + 1);
	assertM(jobManager.debugHelper.fibersAdded, jobsRun + 2);
	assertM(jobManager.debugHelper.fibersDone, jobsRun + 2);
}

//__gshared long best=0;
void testPerformance() {
	uint iterations = 1000;
	uint packetSize = 1000;
	StopWatch sw;
	sw.start();
	jobManager.debugHelper.resetCounters();
	alias ddd = typeof(&simpleYield);
	UniversalJobGroupNew group = UniversalJobGroupNew(packetSize);
	foreach (int i; 0 .. packetSize) {
		group.add!ddd(&simpleYield);
	}
	//int[] pp=	new int[100];
	foreach (uint i; 0 .. iterations) {
		group.callAndWait();
	}

	assertM(jobManager.debugHelper.jobsAdded, iterations * packetSize);
	assertM(jobManager.debugHelper.jobsDone, iterations * packetSize);
	assertM(jobManager.debugHelper.fibersAdded, iterations * packetSize + iterations);
	assertM(jobManager.debugHelper.fibersDone, iterations * packetSize + iterations);
	sw.stop();
	long perMs = iterations * packetSize / sw.msecs;
	printf("Performacnce performacnce: %dms, perMs: %d\n", cast(int)(sw.msecs), cast(int)(perMs));
	//if(perMs>best)best=perMs;

}

shared int myCounter;
void testUnique() {
	import mutils.job_manager.debug_sink;

	myCounter = 0;
	static void localYield() {
		auto fiberData = getFiberData();
		//DebugSink.add(atomicOp!"+="(myCounter,1));
		jobManager.addThisFiberAndYield(fiberData);
	}

	jobManager.debugHelper.resetCounters();
	//DebugSink.reset();
	uint packetSize = 1000;

	alias ddd = typeof(&localYield);
	UniversalJobGroup!ddd group = UniversalJobGroup!ddd(packetSize);
	foreach (int i; 0 .. packetSize) {
		group.add(&localYield);
	}
	group.callAndWait();

	assertM(jobManager.debugHelper.jobsAdded, packetSize);
	assertM(jobManager.debugHelper.jobsDone, packetSize);
	assertM(jobManager.debugHelper.fibersAdded, packetSize + 1);
	assertM(jobManager.debugHelper.fibersDone, packetSize + 1);
	//DebugSink.verifyUnique(packetSize);
}

void testPerformanceSleep() {
	uint partsNum = 1000;
	uint iterations = 60;
	uint u_secs = 13;

	alias ddd = typeof(&activeSleep);
	UniversalJobGroupNew group = UniversalJobGroupNew(partsNum);
	foreach (int i; 0 .. partsNum) {
		group.add!ddd(&activeSleep, u_secs);
	}
	StopWatch sw;
	sw.start();
	foreach (i; 0 .. iterations) {
		group.callAndWait();
	}

	sw.stop();
	result = cast(float) iterations * u_secs / sw.usecs;

}

alias mat4 = float[16];
void mulMat(mat4[] mA, mat4[] mB, mat4[] mC) {
	assertKM(mA.length == mB.length && mB.length == mC.length);
	foreach (i; 0 .. mA.length) {
		foreach (k; 0 .. 1) {
			mC[i] = mB[i][] * mB[i][];
		}
	}
}

__gshared float result;
__gshared float base = 1;
void testPerformanceMatrix() {
	import std.parallelism;

	uint partsNum = 128;
	uint iterations = 100;
	uint matricesNum = 512 * 64;
	assertKM(matricesNum % partsNum == 0);
	mat4[] matricesA = Mallocator.instance.makeArray!mat4(matricesNum);
	mat4[] matricesB = Mallocator.instance.makeArray!mat4(matricesNum);
	mat4[] matricesC = Mallocator.instance.makeArray!mat4(matricesNum);
	scope (exit) {
		Mallocator.instance.dispose(matricesA);
		Mallocator.instance.dispose(matricesB);
		Mallocator.instance.dispose(matricesC);
	}
	StopWatch sw;
	sw.start();
	jobManager.debugHelper.resetCounters();
	uint step = matricesNum / partsNum;

	alias ddd = typeof(&mulMat);
	UniversalJobGroupNew group = UniversalJobGroupNew(partsNum);
	foreach (int i; 0 .. partsNum) {
		group.add!ddd(&mulMat, matricesA[i * step .. (i + 1) * step],
				matricesB[i * step .. (i + 1) * step], matricesC[i * step .. (i + 1) * step]);
	}
	foreach (i; 0 .. iterations) {
		group.callAndWait();
	}

	sw.stop();
	result = cast(float) iterations * matricesNum / sw.usecs;
	printf("Performacnce matrix: %dms\n", cast(int)(sw.msecs));
}

void testForeach() {
	int[200] ints;
	shared uint sum = 0;
	foreach (ref int el; ints.multithreaded) {
		atomicOp!"+="(sum, 1);
		activeSleep(100); //simulate load for 100us
	}
	foreach (ref int el; ints.multithreaded) {
		activeSleep(100);
	}
	assertKM(sum == 200);
}

void testGroupStart() {
	if (jobManager.threadsCount == 1) {
		return;
	}
	uint partsNum = 100;

	alias ddd = typeof(&activeSleep);
	UniversalJobGroup!ddd group = UniversalJobGroup!ddd(partsNum);
	foreach (int i; 0 .. partsNum) {
		group.add(&activeSleep, 10);
	}
	group.start();
	activeSleep(10);
	assertKM(group.counter.count > 0 && !group.counter.countedToZero());
	Thread.sleep(1000);
	//activeSleep(1000_000);
	assertKM(group.areJobsDone);

}

void testGroupsDependicesFuncA(int[] arr) {
	foreach (ref el; arr) {
		el = 1;
	}
}

void testGroupsDependicesFuncB(int[] arr) {
	foreach (ref el; arr) {
		el = 1_000_000;
	}
}

void testGroupsDependicesFuncC(int[] arr) {
	foreach (ref el; arr) {
		el *= 201;
	}
}

void testGroupsDependicesFuncD(int[] arr) {
	foreach (ref el; arr) {
		el -= 90;
	}
}

void testGroupsDependicesFuncE(int[] arrA, int[] arrB) {
	assertKM(arrA.length == arrB.length);
	foreach (i; 0 .. arrA.length) {
		arrA[i] += arrB[i];
		arrA[i] *= -1;
	}
}

void testGroupsDependices() {

	enum uint partsNum = 512;
	enum uint elementsNum = 512 * 512;
	enum uint step = elementsNum / partsNum;
	int[] elements = Mallocator.instance.makeArray!int(elementsNum);
	int[] elements2 = Mallocator.instance.makeArray!int(elementsNum);
	scope (exit) {
		Mallocator.instance.dispose(elements);
		Mallocator.instance.dispose(elements2);
	}
	alias ddd = void function(int[]);
	alias dddSum = void function(int[], int[]);

	auto groupA = UniversalJobGroupNew();
	auto groupB = UniversalJobGroupNew();
	auto groupC = UniversalJobGroupNew();
	auto groupD = UniversalJobGroupNew();
	auto groupE = UniversalJobGroupNew();
	/*groupA.name="groupA";
	groupB.name="groupB";
	groupC.name="groupC";
	groupD.name="groupD";
	groupE.name="groupE";*/

	foreach (int i; 0 .. partsNum) {
		groupA.add!ddd(&testGroupsDependicesFuncA, elements[i * step .. (i + 1) * step]);
		groupB.add!ddd(&testGroupsDependicesFuncB, elements2[i * step .. (i + 1) * step]);
		groupC.add!ddd(&testGroupsDependicesFuncC, elements[i * step .. (i + 1) * step]);
		groupD.add!ddd(&testGroupsDependicesFuncD, elements[i * step .. (i + 1) * step]);
		groupE.add!dddSum(&testGroupsDependicesFuncE,
				elements[i * step .. (i + 1) * step], elements2[i * step .. (i + 1) * step]);
	}

	//---------- groupKK ------------
	//groupA -> groupC -> groupD -> |
	//groupB ->                     | groupE

	//groupE.runOnJobsDone = true;
	groupE.dependantOn(&groupD);
	groupE.dependantOn(&groupB);

	groupC.dependantOn(&groupA);
	groupD.dependantOn(&groupC);

	groupA.start();
	groupB.start();

	groupE.waitForCompletion();

	foreach (el; elements) {
		assertM(el, -1_000_111);
	}
}

void testUnbalancedGroups() {

	enum uint groupsNum = 32;
	alias ddd = void function(uint);

	auto groupEnd = UniversalJobGroupNew();
	UniversalJobGroupNew[groupsNum] groups;

	foreach (ref group; groups) {
		group.add!ddd(&simpleSleep, 100);
		foreach (i; 0 .. 32) {
			group.add!ddd(&simpleSleep, 0);
		}
		groupEnd.dependantOn(&group);
	}

	StopWatch sw;
	sw.start();
	foreach (ref group; groups) {
		group.start();
	}

	groupEnd.waitForCompletion();

	sw.stop();
	printf("Performacnce unbalanced: %dms\n", cast(int)(sw.msecs));
}

void testWaitForGroup() {
	alias ddd = void function(uint);

	UniversalJobGroupNew groupA;
	UniversalJobGroupNew groupEnd;
	/*groupA.name="groupA";
	groupEnd.name="groupEnd";*/
	groupEnd.dependantOn(&groupA);
	groupA.add!ddd(&simpleSleep, 0);
	groupA.start();
	//Thread.sleep(100);
	groupA.waitForCompletion();
	//Thread.sleep(100);
	//groupEnd.waitForCompletion();
}


void test(uint threadsNum = 16) {
	import core.memory;

	GC.disable();
	static void startTest() {
		foreach (i; 0 .. 1) {
			alias UnDel = void delegate();
			testForeach();
			makeTestJobsFrom(&testFiberLockingToThread, 100);
			callAndWait!(UnDel)((&testUnique).toDelegate);
			callAndWait!(UnDel)((&testGroupsDependices).toDelegate);
			callAndWait!(UnDel)((&testWaitForGroup).toDelegate);
			callAndWait!(UnDel)((&testPerformance).toDelegate);	
			callAndWait!(UnDel)((&testPerformanceMatrix).toDelegate);
			callAndWait!(UnDel)((&testPerformanceSleep).toDelegate);
			callAndWait!(UnDel)((&testUnbalancedGroups).toDelegate);
			//callAndWait!(UnDel)((&testGroupStart).toDelegate);// Has to have long sleep
			callAndWait!(UnDel)((&testRandomRecursionJobs).toDelegate);
		}
		//writeln(best);

	}

	jobManager.startMainLoop(&startTest, threadsNum);
	jobManager.clear();
}

void testScalability() {
	foreach (int i; 1 .. 44) {
		printf(" %d ", i);
		test(i);
	}
}

unittest {
	//test(4);
}
