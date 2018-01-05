/**
Module implements multithreated job manager with fibers (coroutines).
Thanks to fibers any task can be stopped in the middle of execution and started again by this manager.
Fibers are bound to one thread due to TLS issues and performance reasons.
 */
module mutils.job_manager.manager_multithreated;

import core.atomic;
import core.stdc.stdio;
import core.sys.posix.stdlib: random;


import mutils.thread : Thread,Fiber;

import std.functional : toDelegate;

import mutils.job_manager.fiber_cache;
import mutils.job_manager.manager_utils;
import mutils.container_shared.shared_queue;


enum threadsPerCPU=4;


alias JobVector=LowLockQueue!(JobDelegate*,bool);
//alias JobVector=LockedVector!(JobDelegate*);
//alias JobVector=LockedVectorBuildIn!(JobDelegate*);

alias FiberVector=LowLockQueue!(FiberData,bool);
//alias FiberVector=LockedVector!(FiberData);
//alias FiberVector=LockedVectorBuildIn!(FiberData);


//alias CacheVector=FiberNoCache;
//alias CacheVector=FiberOneCache;
//alias CacheVector=FiberVectorCache;
alias CacheVector=FiberTLSCache;


__gshared JobManager jobManager;

struct JobManager{
	struct DebugHelper{
		align(64)shared uint jobsAdded;
		align(64)shared uint jobsDone;
		align(64)shared uint fibersAdded;
		align(64)shared uint fibersDone;
		
		void resetCounters(){
			{
				atomicStore(jobsAdded, 0);
				atomicStore(jobsDone, 0);
				atomicStore(fibersAdded, 0);
				atomicStore(fibersDone, 0);
			}
		}
		void jobsAddedAdd  (int num=1){	 atomicOp!"+="(jobsAdded,  num); }
		void jobsDoneAdd   (int num=1){	 atomicOp!"+="(jobsDone,   num); }
		void fibersAddedAdd(int num=1){	 atomicOp!"+="(fibersAdded,num); }
		void fibersDoneAdd (int num=1){	 atomicOp!"+="(fibersDone, num); }

		
		
	}
	DebugHelper debugHelper;

	//jobs managment
	private JobVector waitingJobs;
	enum uint threadsCountT=32;
	//fibers managment
	private FiberVector[threadsCountT] waitingFibers;
	//thread managment
	private Thread[threadsCountT] threadPool;
	bool exit;


	private void initialize(uint threadsCount=0){
		assert(threadsCountT==threadsCount);
		foreach(ref f;waitingFibers)f.initialize();
		foreach(uint i;0..threadsCount){
			threadPool[i].threadNum=i;
			threadPool[i].setDg(&threadRunFunction);
		}

		waitingJobs.initialize();
		version(Android)rt_init();
	}
	void start(){
		foreach(ref thread;threadPool){
			thread.start();
		}
	}
	void startMainLoop(void function() mainLoop,uint threadsCount=0){
		startMainLoop(mainLoop.toDelegate,threadsCount);
	}
	void startMainLoop(JobDelegate mainLoop,uint threadsCount=0){
		
		align(64) shared bool endLoop=false;
		static struct NoGcDelegateHelper
		{
			JobDelegate del;
			shared bool* endPointer;

			this(JobDelegate del,ref shared bool end){
				this.del=del;
				endPointer=&end;
			}

			void call() { 
				del();
				atomicStore(*endPointer,true);			
			}
		}

		NoGcDelegateHelper helper=NoGcDelegateHelper(mainLoop,endLoop);
		initialize(threadsCount);
		auto del=&helper.call;
		start();
		addJob(&del);
		waitForEnd(endLoop);
		end();

		
	}

	void waitForEnd(ref shared bool end){
		bool wait=true;
		do{
			wait= !atomicLoad(end);
			foreach(ref th; threadPool){
				if(!th.isRunning){
					wait=false;
				}
			}
			Thread.sleep(10);
		}while(wait);
	}
	void end(){
		exit=true;
		foreach(ref thread;threadPool){
			thread.join;
		}
		version(Android)rt_close();

	}

	size_t threadsNum(){
		return threadPool.length;
	}

	
	void addFiber(FiberData fiberData){
		assert(waitingFibers.length==threadPool.length);
		assert(fiberData.fiber.state!=Fiber.State.TERM);//  && fiberData.fiber.state!=Fiber.State.EXEC - cannot be added because addThisFiberAndYield violates this assertion
		debugHelper.fibersAddedAdd();
		waitingFibers[fiberData.threadNum].add(fiberData);
	}

	// Only for tests
	void addThisFiberAndYield(FiberData thisFiber){
		addFiber(thisFiber);
		Fiber.yield();
	}

	void addJob(JobDelegate* del){
		debugHelper.jobsAddedAdd();
		waitingJobs.add(del);
	}
	void addJobs(JobDelegate*[] dels){
		debugHelper.jobsAddedAdd(cast(int)dels.length);
		waitingJobs.add(dels);
	}
	void addJobAndYield(JobDelegate* del){
		addJob(del);
		Fiber.yield();
	}
	void addJobsAndYield(JobDelegate*[] dels){
		addJobs(dels);
		Fiber.yield();
	}

	
	CacheVector fibersCache;
	uint fibersMade;

	Fiber allocateFiber(JobDelegate del){
		Fiber fiber;
		fiber=fibersCache.getData(jobManagerThreadNum,cast(uint)threadPool.length);
		assert(fiber.state==Fiber.State.TERM);
		assert(fiber.myThreadNum==jobManagerThreadNum);
		fiber.reset(del);
		fibersMade++;
		return fiber;
	}
	void deallocateFiber(Fiber fiber){
		//fiber.threadStart=null;
		fibersCache.removeData(fiber,jobManagerThreadNum,cast(uint)threadPool.length);
	}
	void runNextJob(){
		//printf("threadRunFunction %d\n", jobManagerThreadNum);
		static int nothingToDoNum=0;
		static int dummySink=0;
		Fiber fiber;
		FiberData fd=waitingFibers[jobManagerThreadNum].pop;
		FiberData varInit;
		if(fd!=varInit){
			//printf("continue fiber %d\n", jobManagerThreadNum);
			fiber=fd.fiber;
			debugHelper.fibersDoneAdd();
		}else if( !waitingJobs.empty ){
			JobDelegate* job;
			job=waitingJobs.pop();
			//printf("are jobs %d\n", jobManagerThreadNum);
			if(job !is null){
				//printf("call new job %d\n", jobManagerThreadNum);
				debugHelper.jobsDoneAdd();
				fiber=allocateFiber(*job);
			}	
		}
		//nothing to do
		if(fiber is null ){
			//printf("no fiber\n");
						nothingToDoNum++;
						if(nothingToDoNum>5){
								Thread.sleep(1);
				//foreach(i;0..random()%2000)dummySink+=random()%2;//backoff
								nothingToDoNum=0;
							}else{
								foreach(i;0..random()%20)dummySink+=random()%2;//backoff
							}
			return;
		}
		//printf("call fiber %d\n", jobManagerThreadNum);
		//do the job
		nothingToDoNum=0;
		assert(fiber.state==Fiber.State.HOLD);
		fiber.call();

		//reuse fiber
		if(fiber.state==Fiber.State.TERM){
			deallocateFiber(fiber);
		}
	}


	void threadRunFunction(){
		Fiber.initializeStatic();
		while(!exit){
			runNextJob();
		}
	}
	
}


