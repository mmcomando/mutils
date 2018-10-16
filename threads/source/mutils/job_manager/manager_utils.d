﻿/**
 Modules contains basic structures for job manager ex. FiberData, Counter. 
 It also contains structures/functions which extens functionality of job manager like:
 - UniversalJob - job with parameters and return value
 - UniversalJobGroup - group of jobs 
 - multithreaded - makes foreach execute in parallel
 */
module mutils.job_manager.manager_utils;

import core.atomic;
import core.stdc.stdio;
import core.stdc.string : memcpy, memset;
import std.algorithm : map;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.traits : Parameters;

import mutils.job_manager.manager;
import mutils.job_manager.utils;
import mutils.thread;
import mutils.thread : Fiber;

alias jobManagerThreadNum = Thread.getThisThreadNum; //thread local var

alias JobDelegate = void delegate();

struct FiberData {
	Fiber fiber;
	uint threadNum;
}

FiberData getFiberData() {
	Fiber fiber = Fiber.getThis();
	//printf("getFiberData fiber: %p\n", fiber);
	assert(fiber !is null);
	return FiberData(fiber, jobManagerThreadNum);
}

struct Counter {
	enum uint invalidCount = 10000;

	align(64) shared int count;
	align(64) FiberData waitingFiber;

	this(uint count) {
		this.count = count;
	}

	bool countedToZero() {
		return atomicLoad(count) == invalidCount;
	}

	void decrement() {
		assert(atomicLoad(count) < invalidCount - 1000);

		atomicOp!"-="(count, 1);
		bool ok = cas(&count, 0, invalidCount);
		if (ok && waitingFiber.fiber !is null) {
			jobManager.addFiber(waitingFiber);
			//waitingFiber.fiber=null;//makes deadlock maybe atomicStore would help or it shows some bug??
			//atomicStore(waitingFiber.fiber,null);//has to be shared ignore for now
		}

	}
}

struct UniversalJob(Delegate) {
	alias UnDelegate = UniversalDelegate!Delegate;
	UnDelegate unDel; //user function to run, with parameters and return value
	JobDelegate runDel; //wraper to decrement counter on end
	Counter* counter;
	void runWithCounter() {
		assert(counter !is null);
		unDel.callAndSaveReturn();
		static if (multithreadedManagerON) {
			counter.decrement();
		}
	}
	//had to be allcoated my Mallocator
	void runAndDeleteMyself() {
		unDel.callAndSaveReturn();
		Mallocator.instance.dispose(&this);
	}

	void initialize(Delegate del, Parameters!(Delegate) args) {
		unDel = makeUniversalDelegate!(Delegate)(del, args);
		//runDel=&run;
	}

}
//It is faster to add array of jobs
struct UniversalJobGroup222 {
	import mutils.container.vector;

	enum uint invalidCount = 10000;
	alias Delegate = void delegate();

	bool runOnJobsDone;
	bool spawnOnDependencyFulfilled;
	align(64) shared int dependicesWaitCount;
	Vector!(UniversalJobGroup222*) children;

	Vector!Job jobs;
	Vector!(JobDelegate*) jobPointers;

	align(64) shared int countJobsToBeDone;
	align(64) FiberData waitingFiber;

	static struct Job {
		UniversalJobGroup222* group;
		Delegate delegateToCall;
		Delegate delegateJob; // JobManager takes pointer to delegate, so there will be stored callJob delegate (&callJob)

		void callJob() {
			delegateToCall();

			atomicOp!"-="(group.countJobsToBeDone, 1);
			bool ok = cas(&group.countJobsToBeDone, 0, invalidCount);
			if (ok) {
				group.onJobsCounterZero();
			}
		}

	}

	void dependantOn(UniversalJobGroup222* parent) {
		parent.children ~= &this;
		atomicOp!"+="(dependicesWaitCount, 1);
		//dependicesWaitCount += 1;
	}

	import std.stdio;

	void onJobsCounterZero() {
		//writeln("onJobsCounterZero");
		decrementChildrenDependices();


		if (runOnJobsDone) {
			//writeln("runOnJobsDone");
			jobManager.addFiber(waitingFiber);
		}
	}

	void decrementChildrenDependices() {
		//writeln("decrementChildrenDependices: ", children.length);
		foreach (UniversalJobGroup222* group; children) {
			assert(atomicLoad(group.dependicesWaitCount) < invalidCount - 1000);

			atomicOp!"-="(group.dependicesWaitCount, 1);
			bool ok = cas(&group.dependicesWaitCount, 0, invalidCount);
			if (ok) {
				group.onDependicesCounterZero();
			}

		}
	}

	void onDependicesCounterZero() {
		//writeln("onDependicesCounterZero");
		//assert(!(runOnJobsDone && spawnOnDependencyFulfilled),
		//		"runOnJobsDone and spawnOnDependencyFulfilled can not be true at once");

		if (spawnOnDependencyFulfilled) {
			//writeln("spawnOnDependencyFulfilled");
			start();
		}
	}

	void start() {
		setUpJobs();
		//counter.waitingFiber = getFiberData();
		jobManager.addJobs(jobPointers[]);
		//decrementChildrenDependices();
	}

	void waitForDependices() {
		runOnJobsDone = true;
		waitingFiber = getFiberData();
		Fiber.yield();
	}

	void add(Delegate del) {
		jobs ~= Job(&this, del);
	}

	auto setUpJobs() {
		countJobsToBeDone = cast(int) jobs.length;
		jobPointers.length = jobs.length;
		foreach (i, ref jj; jobs) {
			jj.delegateJob = &jj.callJob;
			jobPointers[i] = &jj.delegateJob;
		}
	}
}

//It is faster to add array of jobs
struct UniversalJobGroup(Delegate) {
	alias DelegateOnEnd = void delegate();
	alias UnJob = UniversalJob!(Delegate);
	Counter counter;
	uint jobsAdded;
	UnJob[] unJobs;
	JobDelegate*[] dels;
	DelegateOnEnd delegateOnEnd;

	@disable this();
	@disable this(this);

	this(uint jobsNum) {
		mallocatorAllocate(jobsNum);
	}

	~this() {
		mallocatorDeallocate();
	}

	void add(Delegate del, Parameters!(Delegate) args) {
		unJobs[jobsAdded].initialize(del, args);
		jobsAdded++;
	}

	deprecated("Use callAndWait") auto wait() {
		static if (UnJob.UnDelegate.hasReturn) {
			return callAndWait();
		} else {
			callAndWait();
		}
	}

	void setEndFunction(DelegateOnEnd del) {
		delegateOnEnd = del;
	}

	void callAndRunEndFunction() {
		//static assert(!UnJob.UnDelegate.hasReturn,
		//		"UniversalJobGroup delegate can not have return value when callAndRunEndFunction() is used");
		setUpJobs();
		counter.waitingFiber = getFiberData();
		jobManager.addJobsAndYield(dels[0 .. jobsAdded]);
		assert(delegateOnEnd !is null, "delegateOnEnd can not be null");
		delegateOnEnd();
	}

	//Returns data like getReturnData
	auto callAndWait() {
		setUpJobs();
		counter.waitingFiber = getFiberData();
		jobManager.addJobsAndYield(dels[0 .. jobsAdded]);
		static if (UnJob.UnDelegate.hasReturn) {
			return getReturnData();
		}
	}

	bool areJobsDone() {
		return counter.countedToZero();
	}

	///Returns range so you can allocate it as you want
	///But remember: returned data lives as long as this object
	auto getReturnData()() {
		static assert(UnJob.UnDelegate.hasReturn);
		assert(areJobsDone);
		return unJobs.map!(a => a.unDel.result);
	}

	auto start() {
		setUpJobs();
		jobManager.addJobs(dels[0 .. jobsAdded]);
	}

private:
	auto setUpJobs() {
		counter.count = jobsAdded;
		foreach (i, ref unJob; unJobs[0 .. jobsAdded]) {
			unJob.counter = &counter;
			unJob.runDel = &unJob.runWithCounter;
			dels[i] = &unJob.runDel;
		}
	}

	void mallocatorAllocate(uint jobsNum) {
		unJobs = Mallocator.instance.makeArray!(UnJob)(jobsNum);
		dels = Mallocator.instance.makeArray!(JobDelegate*)(jobsNum);
	}

	void mallocatorDeallocate() {
		memset(unJobs.ptr, 0, UnJob.sizeof * unJobs.length);
		memset(dels.ptr, 0, (JobDelegate*).sizeof * unJobs.length);
		Mallocator.instance.dispose(unJobs);
		Mallocator.instance.dispose(dels);
	}
}

deprecated("Now UniversalJobGroup allcoates memory by itself. Delete call to this function.") string getStackMemory(
		string varName) {
	return "";
}

auto callAndWait(Delegate)(Delegate del, Parameters!(Delegate) args) {
	UniversalJob!(Delegate) unJob;
	unJob.initialize(del, args);
	unJob.runDel = &unJob.runWithCounter;
	Counter counter;
	counter.count = 1;
	counter.waitingFiber = getFiberData();
	unJob.counter = &counter;
	jobManager.addJobAndYield(&unJob.runDel);
	static if (unJob.unDel.hasReturn) {
		return unJob.unDel.result;
	}
}

auto callAndNothing(Delegate)(Delegate del, Parameters!(Delegate) args) {
	static assert(!unJob.unDel.hasReturn);
	UniversalJob!(Delegate)* unJob = Mallocator.instance.make!(UniversalJob!(Delegate));
	unJob.initialize(del, args);
	unJob.runDel = &unJob.runAndDeleteMyself;
	jobManager.addJob(&unJob.runDel);
}

auto multithreaded(T)(T[] slice) {

	static struct Tmp {
		import std.traits : ParameterTypeTuple;

		T[] array;
		int opApply(Dg)(scope Dg dg) {
			static assert(ParameterTypeTuple!Dg.length == 1 || ParameterTypeTuple!Dg.length == 2);
			enum hasI = ParameterTypeTuple!Dg.length == 2;
			static if (hasI)
				alias IType = ParameterTypeTuple!Dg[0];
			static struct NoGcDelegateHelper {
				Dg del;
				T[] arr;
				static if (hasI)
					IType iStart;

				void call() {
					foreach (int i, ref element; arr) {
						static if (hasI) {
							IType iSend = iStart + i;
							int result = del(iSend, element);
						} else {
							int result = del(element);
						}
						assert(result == 0,
								"Cant use break, continue, itp in multithreaded foreach");
					}
				}
			}

			enum partsNum = 16; //constatnt number == easy usage of stack
			if (array.length < partsNum) {
				foreach (int i, ref element; array) {
					static if (hasI) {
						int result = dg(i, element);
					} else {
						int result = dg(element);
					}
					assert(result == 0, "Cant use break, continue, itp in multithreaded foreach");

				}
			} else {
				NoGcDelegateHelper[partsNum] helpers;
				uint step = cast(uint) array.length / partsNum;

				alias ddd = void delegate();
				UniversalJobGroup!ddd group = UniversalJobGroup!ddd(partsNum);
				foreach (int i; 0 .. partsNum - 1) {
					helpers[i].del = dg;
					helpers[i].arr = array[i * step .. (i + 1) * step];
					static if (hasI)
						helpers[i].iStart = i * step;
					group.add(&helpers[i].call);
				}
				helpers[partsNum - 1].del = dg;
				helpers[partsNum - 1].arr = array[(partsNum - 1) * step .. array.length];
				static if (hasI)
					helpers[partsNum - 1].iStart = (partsNum - 1) * step;
				group.add(&helpers[partsNum - 1].call);

				group.callAndWait();
			}
			return 0;

		}
	}

	Tmp tmp;
	tmp.array = slice;
	return tmp;
}
