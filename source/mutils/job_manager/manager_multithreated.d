/**
Module implements multithreated job manager with fibers (coroutines).
Thanks to fibers any task can be stopped in the middle of execution and started again by this manager.
Fibers are bound to one thread due to TLS issues and performance reasons.
 */
module mutils.job_manager.manager_multithreated;

import core.atomic;
import core.cpuid : threadsPerCPU;
import core.thread : Thread,ThreadID,sleep,Fiber;

import std.conv : to;
import std.datetime;
import std.functional : toDelegate;
import std.random : uniform;
import std.stdio : write,writeln,writefln;

import mutils.job_manager.debug_sink;
import mutils.job_manager.fiber_cache;
import mutils.job_manager.manager_utils;
import mutils.container_shared.shared_queue;
import mutils.job_manager.shared_utils;


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


__gshared JobManager jobManager=new JobManager;

class JobManager{
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
	//fibers managment
	private FiberVector[] waitingFibers;
	//thread managment
	private Thread[] threadPool;
	bool exit;

	private void initialize(uint threadsCount=0){
		if(threadsCount==0)threadsCount=threadsPerCPU;
		waitingFibers=mallocator.makeArray!(FiberVector)(threadsCount);
		foreach(ref f;waitingFibers)f=mallocator.make!FiberVector;
		threadPool=mallocator.makeArray!(Thread)(threadsCount);
		foreach(i;0..threadsCount){
			Thread th=mallocator.make!Thread(&threadRunFunction);
			th.name=i.to!string;
			threadPool[i]=th;
		}

		waitingJobs=mallocator.make!JobVector();
		fibersCache=mallocator.make!CacheVector();
	}
	void start(){
		foreach(thread;threadPool){
			thread.start();
		}
	}
	void startMainLoop(void function() mainLoop,uint threadsCount=0){
		startMainLoop(mainLoop.toDelegate,threadsCount);
	}
	void startMainLoop(JobDelegate mainLoop,uint threadsCount=0){
		
		shared bool endLoop=false;
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
			foreach(th;threadPool){
				if(!th.isRunning){
					wait=false;
				}
			}
			Thread.sleep(10.msecs);
		}while(wait);
	}
	void end(){
		exit=true;
		foreach(thread;threadPool){
			thread.join;
		}
	}

	size_t threadsNum(){
		return threadPool.length;
	}

	
	void addFiber(FiberData fiberData){
		assert(waitingFibers.length==threadPool.length);
		assert(fiberData.fiber.state!=Fiber.State.TERM );//&& fiberData.fiber.state!=Fiber.State.EXEC
		debugHelper.fibersAddedAdd();
		waitingFibers[fiberData.threadNum].add(fiberData);//range violation??
	}
	//Only for debug and there it ma cause bugs
	void addThisFiberAndYield(FiberData thisFiber){
		addFiber(thisFiber);//We add running fiber and
		Fiber.yield();//wish that it wont be called before this yield
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
		fiber.reset(del);
		fibersMade++;
		return fiber;
	}
	void deallocateFiber(Fiber fiber){
		fibersCache.removeData(fiber,jobManagerThreadNum,cast(uint)threadPool.length);
	}
	void runNextJob(){
		static int dummySink;
		static int nothingToDoNum;
		
		Fiber fiber;
		FiberData fd=waitingFibers[jobManagerThreadNum].pop;
		if(fd!=FiberData.init){
			fiber=fd.fiber;
			debugHelper.fibersDoneAdd();
		}else if( !waitingJobs.empty ){
			JobDelegate* job;
			job=waitingJobs.pop();
			if(job !is null){
				debugHelper.jobsDoneAdd();
				fiber=allocateFiber(*job);
			}	
		}
		//nothing to do
		if(fiber is null ){
			nothingToDoNum++;
			if(nothingToDoNum>50){
				Thread.sleep(10.usecs);
			}else{
				foreach(i;0..uniform(0,20))dummySink+=uniform(1,2);//backoff
			}
			return;
		}
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
		jobManagerThreadNum=Thread.getThis.name.to!uint;
		
		while(!exit){
			runNextJob();
		}
	}
	
}


