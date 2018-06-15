/**
Module used to store information about executed jobs. 
Information is stored using function pointer and times of start and end of a job.

Data should be retrived by only one thread.
*/
module mutils.job_manager.debug_data;

import std.algorithm : map, joiner;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;

import mutils.container.vector;
import mutils.container_shared.shared_vector;
import mutils.time;

//Hepler types
alias ExecutionVector = Vector!Execution;
alias VectorOfExecutionVectors = LockedVector!ExecutionVector;
//static data
//StopWatch threadLocalWatch;
ExecutionVector threadLocalExecutions;
__gshared VectorOfExecutionVectors globalVectorOfExecutionVectors;

//local data initialization
void initializeDebugData() {
	//threadLocalWatch.start();
	//threadLocalExecutions=Mallocator.instance.make!ExecutionVector;
	globalVectorOfExecutionVectors.add(threadLocalExecutions);
}

void deinitializeDebugData() {
	globalVectorOfExecutionVectors.removeElement(threadLocalExecutions);
	//Mallocator.instance.dispose(threadLocalExecutions);
}

//shared data initialization
shared static this() {
	globalVectorOfExecutionVectors = Mallocator.instance.make!VectorOfExecutionVectors;
}

shared static ~this() {
	Mallocator.instance.dispose(globalVectorOfExecutionVectors);
}

//main functionality
void storeExecution(Execution exec) {
	threadLocalExecutions ~= exec;
}
//thread unsafe
void resetExecutions() {
	foreach (executions; globalVectorOfExecutionVectors[]) {
		executions.reset();
	}
}

//thread unsafe
auto getExecutions() {
	return globalVectorOfExecutionVectors[].map!((a) => a[]).joiner;
}

struct Execution {
	void* funcAddr;
	long startTime;
	long endTime;
	this(void* funcAddr) {
		this.funcAddr = funcAddr;
		startTime = useconds();
	}

	void end() {
		endTime = useconds();
	}

	long dt() {
		return endTime - startTime;
	}

	long ticksPerSecond() {
		return 1_000_000;
	}
}
