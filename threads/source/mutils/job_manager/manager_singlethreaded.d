﻿/**
Module implements singlethreated job manager with fibers (coroutines).
Rather for debugging than for anything else.
 */
module mutils.job_manager.manager_singlethreated;

import std.functional : toDelegate;

import mutils.job_manager.fiber_cache;
import mutils.job_manager.manager_utils;
import mutils.job_manager.shared_utils;
import mutils.job_manager.utils;
import mutils.thread : Fiber;

__gshared JobManager jobManager = new JobManager;

class JobManager {
	struct DebugHelper {
		uint jobsAdded;
		uint jobsDone;
		uint fibersAdded;
		uint fibersDone;

		void resetCounters() {
			jobsAdded = 0;
			jobsDone = 0;
			fibersAdded = 0;
			fibersDone = 0;
		}

		void jobsAddedAdd(int num = 1) {
			jobsAdded += num;
		}

		void jobsDoneAdd(int num = 1) {
			jobsDone += num;
		}

		void fibersAddedAdd(int num = 1) {
			fibersAdded += num;
		}

		void fibersDoneAdd(int num = 1) {
			fibersDone += num;
		}
	}

	DebugHelper debugHelper;
	void initialize(uint threadsCount = 0) {
	}

	void start() {
	}

	void waitForEnd(ref shared bool end) {
	}

	void end() {
	}

	void startMainLoop(void function() mainLoop, uint threadsCount = 0) {
		startMainLoop(mainLoop.toDelegate);
	}

	void startMainLoop(JobDelegate mainLoop, uint threadsCount = 0) {
		initialize();
		addJob(&mainLoop);
		//mainLoop();
	}

	void addFiber(FiberData fiberData) {
		assert(fiberData.fiber.state != Fiber.State.TERM && fiberData.fiber.state
				!= Fiber.State.EXEC);
		debugHelper.fibersAddedAdd();
		fiberData.fiber.call();
		debugHelper.fibersDoneAdd();
	}

	//Only for debug 
	void addThisFiberAndYield(FiberData thisFiber) {
		debugHelper.fibersAddedAdd();
		debugHelper.fibersDoneAdd();
	}

	void addJob(JobDelegate* del) {
		debugHelper.jobsAddedAdd();
		//printStack();
		Fiber fiber = allocateFiber(*del);
		assert(fiber.state != Fiber.State.TERM);
		fiber.call();
		if (fiber.state == Fiber.State.TERM) {
			deallocateFiber(fiber);
		}
		debugHelper.jobsDoneAdd();
	}

	void addJobs(JobDelegate*[] dels) {
		foreach (del; dels) {
			addJob(del);
		}
	}

	void addJobAndYield(JobDelegate* del) {
		addJob(del);
		debugHelper.fibersAddedAdd(); //Counter have started me
		debugHelper.fibersDoneAdd();
	}

	void addJobsAndYield(JobDelegate*[] dels) {
		addJobs(dels);
		debugHelper.fibersAddedAdd(); //Counter have started me
		debugHelper.fibersDoneAdd();
	}

	FiberTLSCache fibersCache;
	Fiber allocateFiber(JobDelegate del) {
		Fiber fiber;
		fiber = fibersCache.getData();
		assert(fiber.state == Fiber.State.TERM);
		fiber.reset(del);
		return fiber;
	}

	void deallocateFiber(Fiber fiber) {
		fibersCache.removeData(fiber);
	}

}
