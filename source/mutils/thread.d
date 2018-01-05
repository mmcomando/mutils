module mutils.thread;

import core.atomic;
import core.stdc.stdio;
import core.sys.posix.pthread;

import std.experimental.allocator;
import std.experimental.allocator.mallocator;

import mutils.bindings.libcoro;
import mutils.container.vector;

void msleep(int msecs){
	import core.sys.posix.unistd;
	usleep(msecs*1000);
}

struct Mutex{
	__gshared static pthread_mutex_t mutex;
	
	void initialzie(){ pthread_mutex_init(&mutex, null); }
	void lock(){ pthread_mutex_lock(&mutex); }
	void unlock(){ pthread_mutex_unlock(&mutex); }
}


struct MutexSpinLock{	
	align (64) shared bool lockVar;

	void initialzie(){}
	void lock(){ while( !cas(&lockVar, false, true) ){ } }
	void unlock(){ atomicStore(lockVar, false); }
}



extern (C) void rt_moduleTlsCtor();
extern(C) void rt_moduleTlsDtor();

extern(C) void* threadRunFunction(void* threadVoid){
	static __gshared MutexSpinLock lock;
	import core.thread: thread_attachThis, thread_detachThis;
	Thread* th=cast(Thread*)threadVoid;

	lock.lock();// Not sure if locks are required
	//auto stdThread=thread_attachThis();// Crashes program at the end of execution
	rt_moduleTlsCtor();
	lock.unlock();

	Thread.thisThreadd=th;
	th.threadStart();


	lock.lock();
	//thread_detachThis();
	rt_moduleTlsDtor();
	lock.unlock();

	th.reset();
	pthread_exit(null);
	return null;
}



struct Thread{
	@disable this(this);
	alias DG=void delegate();
	DG threadStart;
	pthread_t handle;
	uint threadNum=uint.max;
	static Thread* thisThreadd;

	void setDg(DG dg){
		threadStart=dg;
	}

	void start(){
		int ok=pthread_create(&handle, null, &threadRunFunction, cast(void*)&this);
		assert(ok==0);
	}

	bool isRunning(){
		return true;
	}

	void reset(){
		threadStart=null;
		threadNum=uint.max;
	}

	void join(){
		pthread_join(handle, null);
		handle=handle.init;
		reset();
	}

	static void sleep(int msecs){
		msleep(msecs);
	}

	static Thread* getThis(){
		assert(thisThreadd !is null);
		return thisThreadd;
	}

	static uint getThisThreadNum(){
		Thread* th=Thread.getThis();
		auto thNum=th.threadNum;
		return thNum;
	}

}





enum PAGESIZE=4096*4;

extern(C) void fiberRunFunction(void* threadVoid){
	Fiber th=cast(Fiber)threadVoid;
	while(1){
		//printf("-----\n");
		if(th==Fiber.gRootFiber){
			printf("root\n");

		}
		if(th.myThreadNum!=jobManagerThreadNum){
			printf("myThreadNum th %d %d\n", th.myThreadNum, jobManagerThreadNum);
			printf("myTh th %p %p\n", th.myThread, Thread.getThis);
			printf("NNNNNUUUUUU %p\n", th.threadStart);
		}
		if(th.threadStart==null){
			printf("NNNNNUUUUUULLLLLlll %d %p\n", jobManagerThreadNum, th);
			printf("NNNNNUUUUUU %p\n", th.threadStart);
		}
		assert(th.myThreadNum==jobManagerThreadNum);
		assert(th.myThread==Thread.getThis);
		th.threadStart();
		th.threadStart=null;
		fiber_transfer(th, th.lastFiber, Fiber.State.TERM, true);
	}
	assert(0);
}

void fiber_transfer(Fiber from, Fiber to, Fiber.State fiberfromStateAfterTransfer, bool backFromFiber){
	//printf("switch th(%d) from %p(%d) to %p,      global: %p\n",jobManagerThreadNum, from, from.state, to, cast(void*)gRootFiber);
	if(to!=Fiber.gRootFiber && to.state!=Fiber.State.HOLD){
		printf("fiber transfer statis: of to: %d\n", to.state);
	}
	assert(from !is null);
	assert(to !is null);
	assert( to.state==Fiber.State.HOLD);
	assert( from.state==Fiber.State.EXEC); //Root is special may have any state
	assert(to!=Fiber.gRootFiber || backFromFiber );
	assert(to==Fiber.gRootFiber || to.threadStart !is null);// Root may not have startFunc

	from.state=fiberfromStateAfterTransfer;
	if(!backFromFiber)to.lastFiber=Fiber.gCurrentFiber;
	if(backFromFiber )from.lastFiber=null;
	to.state=Fiber.State.EXEC;
	Fiber.gCurrentFiber=to;
	

	coro_transfer(&from.context, &to.context);
	Fiber.gCurrentFiber=from;
	from.state=Fiber.State.EXEC;
	//to.state=fiberToStateAfterExit;// to state is set by fibercalling to this fiber
	
}

import mutils.job_manager.manager_utils;

final class Fiber{
	static Fiber gCurrentFiber;
	static Fiber gRootFiber;
	//@disable this(this);
	alias DG=void delegate();

	enum State{
		HOLD=0,
		TERM=1,
		EXEC=2,
	}

	DG threadStart;
	size_t pageSize=PAGESIZE*32u;
	State state;
	align(128) coro_context context;
	Fiber lastFiber;
	bool created=false;
	uint myThreadNum=int.max;
	Thread* myThread;

	this(){
		myThreadNum=jobManagerThreadNum;
		myThread=Thread.getThis();
	}

	this(size_t pageSize){
		myThreadNum=jobManagerThreadNum;
		this.pageSize=pageSize;
		myThread=Thread.getThis();
	}

	this(DG dg, size_t pageSize){
		myThreadNum=jobManagerThreadNum;
		threadStart=dg;
		this.pageSize=pageSize;
		myThread=Thread.getThis();
	}

	~this(){
		lastFiber=null;
		state=cast(State)0xffff;
		pageSize=3;
		threadStart=null;
		//coro_destroy(&context);
	}

	void reset(DG dg){
		assert(state == State.TERM);
		state=State.HOLD;
		threadStart=dg;
	}

	__gshared static MutexSpinLock mutex;

	static void initializeStatic(){
		//printf("Fiber.initializeStatic\n");
		gRootFiber=Mallocator.instance.make!(Fiber)();
		assert(gRootFiber.state == State.HOLD);
		mutex.lock();
		coro_create(&gRootFiber.context, null, null, null, 0); 
		mutex.unlock();
		gRootFiber.state=State.EXEC;
		
	}

	void call(){

		if(gCurrentFiber is null){
			gCurrentFiber=gRootFiber;
		}
		

		if(created==false){
			mutex.lock();
			created=true;

			coro_stack stack;

			//import core.stdc.stdlib;
			//void* mem=malloc(pageSize);
			//stack.sptr=mem;
			//stack.ssze=pageSize;
			coro_stack_alloc(&stack, 1024*1024);

			//printf("stack(%p), size %d\n", stack.sptr ,stack.ssze);
			//printf("create(%d) corr(%p)\n", jobManagerThreadNum ,this);
			assert(myThreadNum==jobManagerThreadNum);
			
			coro_create (&context, &fiberRunFunction, cast(void*)this, stack.sptr, stack.ssze);		

			mutex.unlock();
		}
		assert(jobManagerThreadNum==myThreadNum);
		
		auto fib=gCurrentFiber;
		assert(this.threadStart !is null);
		fiber_transfer(fib, this, Fiber.State.HOLD, false);

		

	}

	static void yield(){
		//printf("yield %d\n", jobManagerThreadNum);		
		auto fib=gCurrentFiber;
		assert(fib!=gRootFiber);
		fiber_transfer(fib, fib.lastFiber, Fiber.State.HOLD, true);
	}

	static Fiber getThis(){
		if(gCurrentFiber is null || gCurrentFiber.state!= Fiber.State.EXEC ){	
			return null;
		}
		assert(gCurrentFiber!=gRootFiber);
		return gCurrentFiber;
	}

}

unittest{
	import core.memory;
	GC.disable();
	Fiber fb;
	enum nestageLevelMax=10;
	int nestageLevel=0;

	void testNest(){
		if(nestageLevel>=nestageLevelMax){
			return;
		}
		nestageLevel++;
		Fiber f=new Fiber(&testNest, PAGESIZE*32u);
		f.call();
	}

	void testFunc(){
		assert(Fiber.getThis().lastFiber!=Fiber.getThis());
		assert(Fiber.getThis().lastFiber==fb);
		Fiber.yield();
		assert(Fiber.getThis().lastFiber!=Fiber.getThis());
		assert(Fiber.getThis().lastFiber==fb);
		Fiber.yield();
		assert(Fiber.getThis().lastFiber!=Fiber.getThis());
		assert(Fiber.getThis().lastFiber==fb);	

		Fiber f=new Fiber(&testNest, PAGESIZE*32u);
		f.call();
	}

	void mainFiber(){
		assert(Fiber.getThis()==fb);
		Fiber f=new Fiber(&testFunc, PAGESIZE*32u);
		assert(f.state==Fiber.State.HOLD);
		f.call();
		assert(f.state==Fiber.State.HOLD);
		f.call();
		assert(f.state==Fiber.State.HOLD);
		f.call();
		assert(f.state==Fiber.State.TERM);
		assert(Fiber.getThis()==fb);
	}

	void threadStart(){
		Fiber.initializeStatic();
		fb=new Fiber(&mainFiber, PAGESIZE*32u);
		assert(fb.state==Fiber.State.HOLD);
		fb.call();
		assert(fb.state==Fiber.State.TERM);
		assert(nestageLevel==nestageLevelMax);
	}
	Thread th;
	th.threadNum=5674;
	th.setDg(&threadStart);
	th.start();
	th.join();
}



