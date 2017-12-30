module mutils.thread;

import core.sys.posix.pthread;
import core.stdc.stdio;
import mutils.container.vector;

extern(C) void* threadRunFunction(void* threadVoid){
	Thread th=cast(Thread)threadVoid;
	th.threadStart();
	pthread_exit(null);
	return null;
}


__gshared Vector!Thread gAllThreads;

class Thread{
	alias DG=void delegate();
	DG threadStart;
	pthread_t handle;
	string name;

	this(DG dg){
		threadStart=dg;
		gAllThreads~=this;
	}

	void start(){
		int ok=pthread_create(&handle, null, &threadRunFunction, cast(void*)this);
		assert(ok==0);
	}

	bool isRunning(){
		return true;
	}

	void join(){
		pthread_join(handle, null);
	}

	static void sleep(T)(T vs){
		mutils.thread.sleep(1);
	}

	static Thread getThis(){
		pthread_t currentThread=pthread_self();
		foreach(th; gAllThreads){
			if(th.handle==currentThread){
				return th;
			}
		}
		assert(0);
	}

}

enum PAGESIZE=4096*4;

extern(C) void fiberRunFunction(void* threadVoid){
	Fiber th=cast(Fiber)threadVoid;
	while(1){

		//atomicFence();
		//import mutils.job_manager.utils;
		//string name=functionName(th.threadStart.funcptr);
		//printf("fiber call func (%p) %*s\n", th.threadStart.funcptr, name.length, name.ptr);
		th.threadStart();
		fiber_transfer(gCurrentFiber, gCurrentFiber.lastFiber, Fiber.State.TERM, true);
	}
	assert(0);
}

import core.atomic;
__gshared Fiber[100] gCurrentFib;

Fiber gCurrentFiber(){
	//atomicFence();
	Fiber tmp=gCurrentFib[jobManagerThreadNum];
	//atomicFence();
	return tmp;
}

void gCurrentFiber(Fiber fib){
	//atomicFence();
	gCurrentFib[jobManagerThreadNum]=fib;
	//atomicFence();
}
__gshared Fiber gRootFiber= new Fiber;

void fiber_transfer(Fiber from, Fiber to, Fiber.State fiberfromStateAfterTransfer, bool backFromFiber){
	//printf("switch th(%d) from %p(%d) to %p,      global: %p\n",jobManagerThreadNum, from, from.state, to, gRootFiber);
	assert(to==gRootFiber || to.state==Fiber.State.HOLD);
	assert(from==gRootFiber || from.state==Fiber.State.EXEC); //Root is special may have any state
	assert(backFromFiber || to!=gRootFiber);
	assert(to==gRootFiber || to.threadStart !is null);// Root may not have startFunc

	from.state=fiberfromStateAfterTransfer;
	if(!backFromFiber)to.lastFiber=gCurrentFiber;
	if(backFromFiber )from.lastFiber=null;
	to.state=Fiber.State.EXEC;
	gCurrentFiber=to;
	//atomicFence();
	coro_transfer(&from.context, &to.context);
	gCurrentFiber=from;
	from.state=Fiber.State.EXEC;
	//to.state=fiberToStateAfterExit;// to state is set by fibercalling to this fiber
	//atomicFence();
}
import mutils.job_manager.manager_utils;

class Fiber{
	alias DG=void delegate();

	enum State{
		HOLD=0,
		TERM=1,
		EXEC=2,
	}
	DG threadStart;
	size_t pageSize;
	State state;
	coro_context context;
	Fiber lastFiber;
	bool created=false;

	this(){}

	this(size_t pageSize){
		this.pageSize=pageSize;
	}

	this(DG dg, size_t pageSize){
		threadStart=dg;
		this.pageSize=pageSize;
	}

	void reset(DG dg){
		state=State.HOLD;
		threadStart=dg;
	}
	align (64) shared bool lock;
	__gshared static bool inited=false;

	void call(){
	//	printf("gRootFiber.state(%d): %d\n", jobManagerThreadNum, gRootFiber.state);
		if(!inited){
			while( !cas(&lock, false, true )){ } 	// acquire exclusivity
			//atomicFence();
			if(!inited){
				assert(gRootFiber.state == State.HOLD);
				printf("create global %p, state(%d): %d\n", gRootFiber, jobManagerThreadNum, gRootFiber.state);
				coro_create(&gRootFiber.context, null, null, null, 0); 
				gCurrentFiber=gRootFiber;
				//gRootFiber.state=State.EXEC;
				inited=true;
			}
			atomicStore(lock, false);		// release exclusivity
		}

		if(gCurrentFiber is null){
			gCurrentFiber=gRootFiber;
		}
		//atomicFence();

		if(created==false){
			created=true;
			//import core.stdc.stdlib;
			//void* mem=malloc(pageSize);

			while( !cas(&lock, false, true )){ } 	// acquire exclusivity
			coro_stack stack;
			coro_stack_alloc(&stack, 1024*1024*2);
			printf("stack size %d", stack.ssze);

			coro_create (&context, &fiberRunFunction, cast(void*)this, stack.sptr, stack.ssze); 

			atomicStore(lock, false);		// release exclusivity
			printf("create fiber %p\n", this);
		}
		fiber_transfer(gCurrentFiber, this, Fiber.State.HOLD, false);
	}

	static void yield(){
		//printf("yield\n");
		fiber_transfer(gCurrentFiber, gCurrentFiber.lastFiber, Fiber.State.HOLD, true);
	}

	static Fiber getThis(){
		if(gCurrentFiber is null){
			printf("getThis gCurrentFiber is null\n");			
		}
		if(gCurrentFiber !is null && gCurrentFiber.state!= Fiber.State.EXEC){	
			printf("getThis %p(%d)gCurrentFiber.state!= Fiber.State.EXEC\n", gRootFiber, gCurrentFiber.state);		
		}
		if(gCurrentFiber is null || gCurrentFiber.state!= Fiber.State.EXEC ){	
			return null;
		}
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
		printf("testFunc Start\n");
		assert(Fiber.getThis().lastFiber!=Fiber.getThis());
		assert(Fiber.getThis().lastFiber==fb);
		Fiber.yield();
		printf("testFunc Middle\n");
		assert(Fiber.getThis().lastFiber!=Fiber.getThis());
		assert(Fiber.getThis().lastFiber==fb);
		Fiber.yield();
		printf("testFunc End\n");
		assert(Fiber.getThis().lastFiber!=Fiber.getThis());
		assert(Fiber.getThis().lastFiber==fb);	

		Fiber f=new Fiber(&testNest, PAGESIZE*32u);
		f.call();
	}

	void mainFiber(){
		printf("mainFiber Start\n");
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
		printf("mainFiber End\n");
	}

	fb=new Fiber(&mainFiber, PAGESIZE*32u);
	assert(Fiber.getThis() is null);
	assert(fb.state==Fiber.State.HOLD);
	fb.call();
	assert(fb.state==Fiber.State.TERM);
	printf("%d\n", cast(int)fb.state);
	assert(Fiber.getThis() == gRootFiber);
	assert(nestageLevel==nestageLevelMax);
}


extern(C)  uint sleep(uint seconds);



/////////////////////////////////////////////////////////
//////////////////  libcoro


coro_context ctx, mainctx;
coro_stack stack;

extern(C) void coro_body(void *arg)
{
	printf("OK\n");
	coro_transfer(&ctx, &mainctx);
	printf("Back in coro\n");
	coro_transfer(&ctx, &mainctx);
}

extern(C) void test_coro()
{
	coro_create(&mainctx, null, null, null, 0);
	coro_stack_alloc(&stack, 0);
	coro_create(&ctx, &coro_body, null, stack.sptr, stack.ssze);
	printf("Created a coro\n");
	coro_transfer(&mainctx, &ctx);
	printf("Back in main\n");
	coro_transfer(&mainctx, &ctx);
	printf("Back in main again\n");
}

unittest{
	test_coro();
}

enum CORO_VERSION=3;


/*
 * This is the type for the initialization function of a new coroutine.
 */
alias  coro_func= extern(C) void function(void *);

/*
 * A coroutine state is saved in the following structure. Treat it as an
 * opaque type. errno and sigmask might be saved, but don't rely on it,
 * implement your own switching primitive if you need that.
 */
struct coro_context{
	ubyte[256] data;
}

/*
 * This function creates a new coroutine. Apart from a pointer to an
 * uninitialised coro_context, it expects a pointer to the entry function
 * and the single pointer value that is given to it as argument.
 *
 * Allocating/deallocating the stack is your own responsibility.
 *
 * As a special case, if coro, arg, sptr and ssze are all zero,
 * then an "empty" coro_context will be created that is suitable
 * as an initial source for coro_transfer.
 *
 * This function is not reentrant, but putting a mutex around it
 * will work.
 */
extern(C) void coro_create (coro_context *ctx, /* an uninitialised coro_context */
	coro_func coro,    /* the coroutine code to be executed */
	void *arg,         /* a single pointer passed to the coro */
	void *sptr,        /* start of stack area */
	size_t ssze);      /* size of stack area in bytes */

/*
 * The following prototype defines the coroutine switching function. It is
 * sometimes implemented as a macro, so watch out.
 *
 * This function is thread-safe and reentrant.
 */
extern(C) void coro_transfer (coro_context *prev, coro_context *next);

/*
 * The following prototype defines the coroutine destroy function. It
 * is sometimes implemented as a macro, so watch out. It also serves no
 * purpose unless you want to use the CORO_PTHREAD backend, where it is
 * used to clean up the thread. You are responsible for freeing the stack
 * and the context itself.
 *
 * This function is thread-safe and reentrant.
 */
extern(C) void coro_destroy (coro_context *ctx);



struct coro_stack
{
	void *sptr;
	size_t ssze;
	int valgrind_id;
}

/*
 * Try to allocate a stack of at least the given size and return true if
 * successful, or false otherwise.
 *
 * The size is *NOT* specified in bytes, but in units of sizeof (void *),
 * i.e. the stack is typically 4(8) times larger on 32 bit(64 bit) platforms
 * then the size passed in.
 *
 * If size is 0, then a "suitable" stack size is chosen (usually 1-2MB).
 */
extern(C) int coro_stack_alloc (coro_stack *stack, uint size);