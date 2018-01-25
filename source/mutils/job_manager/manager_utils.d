/**
 Modules contains basic structures for job manager ex. FiberData, Counter. 
 It also contains structures/functions which extens functionality of job manager like:
 - UniversalJob - job with parameters and return value
 - UniversalJobGroup - group of jobs 
 - multithreaded - makes foreach execute in parallel
 */
module mutils.job_manager.manager_utils;

import core.atomic;
import core.stdc.string : memset,memcpy;
import core.stdc.stdio;
import mutils.thread : Fiber;

import std.algorithm : map;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.traits : Parameters;

import mutils.job_manager.manager;
import mutils.job_manager.utils;
import mutils.thread;

alias jobManagerThreadNum=Thread.getThisThreadNum;//thread local var

alias JobDelegate=void delegate();

struct FiberData{
	Fiber fiber;
	uint threadNum;
}

FiberData getFiberData(){
	Fiber fiber=Fiber.getThis();
	//printf("getFiberData fiber: %p\n", fiber);
	assert(fiber !is null);
	return FiberData(fiber,jobManagerThreadNum);
}

struct Counter{
	enum uint invalidCoun=10000;

	align (64)shared int count;
	align (64)FiberData waitingFiber;


	this(uint count){
		this.count=count;
	}

	bool countedToZero(){
		return atomicLoad(count)==invalidCoun;
	}

	void decrement(){
		assert(atomicLoad(count)<invalidCoun-1000);
		
		atomicOp!"-="(count, 1);
		bool ok=cas(&count,0,invalidCoun);
		if(ok && waitingFiber.fiber !is null){
			jobManager.addFiber(waitingFiber);
			//waitingFiber.fiber=null;//makes deadlock maybe atomicStore would help or it shows some bug??
			//atomicStore(waitingFiber.fiber,null);//has to be shared ignore for now
		}
		
		
	}
}

struct UniversalJob(Delegate){
	alias UnDelegate=UniversalDelegate!Delegate;
	UnDelegate unDel;//user function to run, with parameters and return value
	JobDelegate runDel;//wraper to decrement counter on end
	Counter* counter;
	void runWithCounter(){
		assert(counter !is null);
		unDel.callAndSaveReturn();
		static if(multithreadedManagerON)counter.decrement();
	}
	//had to be allcoated my Mallocator
	void runAndDeleteMyself(){
		unDel.callAndSaveReturn();
		Mallocator.instance.dispose(&this);
	}
	
	void initialize(Delegate del,Parameters!(Delegate) args){
		unDel=makeUniversalDelegate!(Delegate)(del,args);
		//runDel=&run;
	}
	
}

//It is faster to add array of jobs
struct UniversalJobGroup(Delegate){
	alias UnJob=UniversalJob!(Delegate);
	Counter counter;
	uint jobsNum;
	uint jobsAdded;
	UnJob[] unJobs;
	JobDelegate*[] dels;

	@disable this();
	@disable this(this);

	this(uint jobsNum){
		this.jobsNum=jobsNum;
		mallocatorAllocate();
	}

	~this(){
		mallocatorDeallocate();
	}

	void add(Delegate del,Parameters!(Delegate) args){
		assert(unJobs.length>0 && jobsAdded<jobsNum);
		unJobs[jobsAdded].initialize(del,args);
		jobsAdded++;
	}

	deprecated("Use callAndWait")
	auto wait(){
		static if(UnJob.UnDelegate.hasReturn){
			return callAndWait();
		}else{
			callAndWait();
		}
	}

	//Returns data like getReturnData
	auto callAndWait(){
		setUpJobs();
		counter.waitingFiber=getFiberData();
		jobManager.addJobsAndYield(dels);
		static if(UnJob.UnDelegate.hasReturn){
			return getReturnData();
		}		
	}
	
	bool areJobsDone(){
		return counter.countedToZero();	
	}

	///Returns range so you can allocate it as you want
	///But remember: returned data lives as long as this object
	auto getReturnData()(){
		static assert(UnJob.UnDelegate.hasReturn);
		assert(areJobsDone);
		return unJobs.map!(a => a.unDel.result);
	}

	auto start(){
		setUpJobs();
		jobManager.addJobs(dels);		
	}

private:
	auto setUpJobs(){
		assert(jobsAdded==jobsNum);
		counter.count=jobsNum;
		foreach(i,ref unJob;unJobs){
			unJob.counter=&counter;
			unJob.runDel=&unJob.runWithCounter;
			dels[i]=&unJob.runDel;
		}		
	}

	void mallocatorAllocate(){
		unJobs=Mallocator.instance.makeArray!(UnJob)(jobsNum);
		dels=Mallocator.instance.makeArray!(JobDelegate*)(jobsNum);
	}

	void mallocatorDeallocate(){
		memset(unJobs.ptr,0,UnJob.sizeof*jobsNum);
		memset(dels.ptr,0,(JobDelegate*).sizeof*jobsNum);
		Mallocator.instance.dispose(unJobs);
		Mallocator.instance.dispose(dels);
	}
}

deprecated("Now UniversalJobGroup allcoates memory by itself. Delete call to this function.") string getStackMemory(string varName){	
	return "";
}






auto callAndWait(Delegate)(Delegate del,Parameters!(Delegate) args){
	UniversalJob!(Delegate) unJob;
	unJob.initialize(del,args);
	unJob.runDel=&unJob.runWithCounter;
	Counter counter;
	counter.count=1;
	counter.waitingFiber=getFiberData();
	unJob.counter=&counter;
	jobManager.addJobAndYield(&unJob.runDel);
	static if(unJob.unDel.hasReturn){
		return unJob.unDel.result;
	}
}

auto callAndNothing(Delegate)(Delegate del,Parameters!(Delegate) args){
	static assert(!unJob.unDel.hasReturn);
	UniversalJob!(Delegate)* unJob=Mallocator.instance.make!(UniversalJob!(Delegate));
	unJob.initialize(del,args);
	unJob.runDel=&unJob.runAndDeleteMyself;
	jobManager.addJob(&unJob.runDel);
}

auto multithreaded(T)(T[] slice){
	
	static struct Tmp {
		import std.traits:ParameterTypeTuple;
		T[] array;
		int opApply(Dg)(scope Dg dg)
		{ 
			static assert (ParameterTypeTuple!Dg.length == 1 || ParameterTypeTuple!Dg.length == 2);
			enum hasI=ParameterTypeTuple!Dg.length == 2;
			static if(hasI)alias IType=ParameterTypeTuple!Dg[0];
			static struct NoGcDelegateHelper{
				Dg del;
				T[] arr;
				static if(hasI)IType iStart;
				
				void call() { 
					foreach(int i,ref element;arr){
						static if(hasI){
							IType iSend=iStart+i;
							int result=del(iSend,element);
						}else{
							int result=del(element);
						}
						assert(result==0,"Cant use break, continue, itp in multithreaded foreach");
					}	
				}
			}
			enum partsNum=16;//constatnt number == easy usage of stack
			if(array.length<partsNum){
				foreach(int i,ref element;array){
					static if(hasI){
						int result=dg(i,element);
					}else{
						int result=dg(element);
					}
					assert(result==0,"Cant use break, continue, itp in multithreaded foreach");
					
				}
			}else{
				NoGcDelegateHelper[partsNum] helpers;
				uint step=cast(uint)array.length/partsNum;
				
				alias ddd=void delegate();
				UniversalJobGroup!ddd group=UniversalJobGroup!ddd(partsNum);
				foreach(int i;0..partsNum-1){
					helpers[i].del=dg;
					helpers[i].arr=array[i*step..(i+1)*step];
					static if(hasI)helpers[i].iStart=i*step;
					group.add(&helpers[i].call);
				}
				helpers[partsNum-1].del=dg;
				helpers[partsNum-1].arr=array[(partsNum-1)*step..array.length];
				static if(hasI)helpers[partsNum-1].iStart=(partsNum-1)*step;
				group.add(&helpers[partsNum-1].call);
				
				group.callAndWait();
			}
			return 0;
			
		}
	}
	Tmp tmp;
	tmp.array=slice;
	return tmp;
}






