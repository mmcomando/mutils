/**
Module implements multithreaded job manager with fibers (coroutines).
Thanks to fibers any task can be stopped in the middle of execution and started again by this manager.
Fibers are bound to one thread due to TLS issues and performance reasons.
 */

module mutils.job_manager.manager_multithreaded;
//module mutils.job_manager.manager_multithreadeddd; version(none):

import core.atomic;
import core.stdc.stdio;
import core.stdc.stdlib : rand;
import std.functional : toDelegate;
import std.stdio;

import mutils.container.vector;
import mutils.container_shared.shared_queue;
import mutils.job_manager.fiber_cache;
import mutils.job_manager.manager_utils;
import mutils.thread : Fiber, Thread, Semaphore;

enum threadsPerCPU = 4;

alias JobVector = LowLockQueue!(JobDelegate*);
alias FiberVector = LowLockQueue!(FiberData);

__gshared JobManager jobManager;

struct JobManager {
	struct DebugHelper {
		align(64) shared uint jobsAdded;
		align(64) shared uint jobsDone;
		align(64) shared uint fibersAdded;
		align(64) shared uint fibersDone;

		void resetCounters() {
			{
				atomicStore(jobsAdded, 0);
				atomicStore(jobsDone, 0);
				atomicStore(fibersAdded, 0);
				atomicStore(fibersDone, 0);
			}
		}

		void jobsAddedAdd(int num = 1) {
			debug atomicOp!"+="(jobsAdded, num);
		}

		void jobsDoneAdd(int num = 1) {
			debug atomicOp!"+="(jobsDone, num);
		}

		void fibersAddedAdd(int num = 1) {
			debug atomicOp!"+="(fibersAdded, num);
		}

		void fibersDoneAdd(int num = 1) {
			debug atomicOp!"+="(fibersDone, num);
		}

	}

	int threadsCount;
	DebugHelper debugHelper;
	// Jobs managment
	private int addJobToQueueNum;
	private Vector!JobVector waitingJobs;
	// Fibers managment
	private Vector!FiberTLSCache fibersCache;
	private Vector!FiberVector waitingFibers;
	// Thread managment
	private Vector!Thread threadPool;
	private Vector!Semaphore semaphores;
	private bool exit;

	private void initialize(uint threadsCount = 0) {
		exit = false;

		if (threadsCount == 0)
			threadsCount = threadsPerCPU;
		if (threadsCount == 0)
			threadsCount = 4;

		this.threadsCount = threadsCount;

		waitingFibers.length = threadsCount;
		threadPool.length = threadsCount;
		waitingJobs.length = threadsCount;
		semaphores.length = threadsCount;
		fibersCache.length = threadsCount;

		foreach (uint i; 0 .. threadsCount) {
			waitingFibers[i].initialize();
			semaphores[i].initialize();
			threadPool[i].threadNum = i;
			threadPool[i].setDg(&threadRunFunction);
			waitingJobs[i].initialize();
		}

		version (Android)
			rt_init();
	}

	void clear() {
		foreach (i; 0 .. threadsCount) {
			waitingJobs[i].clear();
			waitingFibers[i].clear();
			fibersCache[i].clear();
			semaphores[i].destroy();
		}
		waitingFibers.clear();
		waitingJobs.clear();
		threadPool.clear();
		fibersCache.clear();
		semaphores.clear();
	}

	void start() {
		foreach (ref thread; threadPool) {
			thread.start();
		}
	}

	void startMainLoop(void function() mainLoop, uint threadsCount = 0) {
		startMainLoop(mainLoop.toDelegate, threadsCount);
	}

	void startMainLoop(JobDelegate mainLoop, uint threadsCount = 0) {

		align(64) shared bool endLoop = false;
		static struct NoGcDelegateHelper {
			JobDelegate del;
			shared bool* endPointer;

			this(JobDelegate del, ref shared bool end) {
				this.del = del;
				endPointer = &end;
			}

			void call() {
				del();
				atomicStore(*endPointer, true);
			}
		}

		NoGcDelegateHelper helper = NoGcDelegateHelper(mainLoop, endLoop);
		initialize(threadsCount);
		auto del = &helper.call;
		start();
		addJob(&del);
		waitForEnd(endLoop);
		end();
	}

	void waitForEnd(ref shared bool end) {
		bool wait = true;
		do {
			wait = !atomicLoad(end);
			foreach (ref th; threadPool) {
				if (!th.isRunning) {
					wait = false;
				}
			}
			Thread.sleep(10);
		}
		while (wait);
	}

	void end() {
		exit = true;
		foreach (i; 0 .. threadsCount) {
			semaphores[i].post();
		}
		foreach (ref thread; threadPool) {
			thread.join();
		}
		version (Android)
			rt_close();

	}

	void addFiber(FiberData fiberData) {
		assert(waitingFibers.length == threadPool.length);
		assert(fiberData.fiber.state != Fiber.State.TERM); //  && fiberData.fiber.state!=Fiber.State.EXEC - cannot be added because addThisFiberAndYield violates this assertion
		debugHelper.fibersAddedAdd();
		waitingFibers[fiberData.threadNum].add(fiberData);
		semaphores[fiberData.threadNum].post();
	}

	// Only for tests - fiber should not add itself to execution
	void addThisFiberAndYield(FiberData thisFiber) {
		addFiber(thisFiber);
		Fiber.yield();
	}

	void addJob(JobDelegate* del) {
		debugHelper.jobsAddedAdd();

		int queueNum = addJobToQueueNum % cast(int) waitingJobs.length;
		waitingJobs[queueNum].add(del);
		semaphores[queueNum].post();
		addJobToQueueNum++;
	}

	void addJobs(JobDelegate*[] dels) {
		debugHelper.jobsAddedAdd(cast(int) dels.length);

		int part = cast(int)(dels.length / waitingJobs.length);
		if (part > 0) {
			foreach (i, ref wj; waitingJobs) {
				wj.add(dels[i * part .. (i + 1) * part]);

				foreach (kkk; 0 .. part) {
					semaphores[i].post();
				}
			}
			dels = dels[part * waitingJobs.length .. $];
		}
		foreach (del; dels) {
			int queueNum = addJobToQueueNum % cast(int) waitingJobs.length;
			waitingJobs[queueNum].add(del);
			semaphores[queueNum].post();
			addJobToQueueNum++;
		}
	}

	void addJobAndYield(JobDelegate* del) {
		addJob(del);
		Fiber.yield();
	}

	void addJobsAndYield(JobDelegate*[] dels) {
		addJobs(dels);
		Fiber.yield();
	}

	Fiber allocateFiber(JobDelegate del, int threadNum) {
		Fiber fiber = fibersCache[threadNum].getData();
		assert(fiber.state == Fiber.State.TERM);
		assert(fiber.myThreadNum == jobManagerThreadNum);
		fiber.reset(del);
		return fiber;
	}

	void deallocateFiber(Fiber fiber, int threadNum) {
		fiber.threadStart = null;
		fibersCache[threadNum].removeData(fiber);
	}

	Fiber getFiberOwnerThread(int threadNum) {
		Fiber fiber;
		FiberData fd = waitingFibers[threadNum].pop;
		if (fd != FiberData.init) {
			fiber = fd.fiber;
			debugHelper.fibersDoneAdd();
		} else {
			JobDelegate* job = waitingJobs[threadNum].pop();
			if (job !is null) {
				debugHelper.jobsDoneAdd();
				fiber = allocateFiber(*job, threadNum);
			}
		}
		return fiber;
	}

	Fiber getFiberThiefThread(int threadNum) {
		Fiber fiber;
		foreach (thSteal; 0 .. threadsCount) {
			if (thSteal == threadNum) {
				continue; // Do not steal from yourself
			}
			if (semaphores[thSteal].tryWait()) {
				JobDelegate* job = waitingJobs[thSteal].pop();
				if (job !is null) {
					debugHelper.jobsDoneAdd();
					fiber = allocateFiber(*job, threadNum);
					break;
				} else {
					semaphores[thSteal].post(); // Can not steal, give owner a chance to take it
				}

			}
		}
		return fiber;
	}

	void threadRunFunction() {
		Fiber.initializeStatic();
		int threadNum = jobManagerThreadNum;
		while (!exit) {
			Fiber fiber;
			if (semaphores[threadNum].tryWait()) {
				fiber = getFiberOwnerThread(threadNum);
			} else {
				fiber = getFiberThiefThread(threadNum);
				if (fiber is null) {
					// Thread does not have own job and can not steal, so wait for a job 
					semaphores[threadNum].wait();
					fiber = getFiberOwnerThread(threadNum);
				}
			}

			// Nothing to do
			if (fiber is null) {
				//return;
				continue;
			}
			// Do the job
			assert(fiber.state == Fiber.State.HOLD);
			fiber.call();

			// Reuse fiber
			if (fiber.state == Fiber.State.TERM) {
				deallocateFiber(fiber, threadNum);
			}
		}
	}

}
