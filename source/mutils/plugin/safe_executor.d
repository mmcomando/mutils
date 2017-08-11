module mutils.plugin.safe_executor;

import core.stdc.signal;
import core.sync.condition;
import core.sync.mutex;
import core.sync.semaphore;
import core.thread;


import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.stdio;
import std.typecons;

import mutils.plugin.safe_executor;
import mutils.container_shared.shared_queue;

version(Posix){
	extern(C) void pthread_exit(void *value_ptr)  nothrow @nogc @system;
	void thisThreadExit() nothrow @nogc @system{
		pthread_exit(null);
	}
}else version(Windows){
	extern(Windows) void ExitThread(uint dwExitCode)  nothrow @nogc @system;
	void thisThreadExit() nothrow @nogc @system{
		ExitThread(0);
	}
}else{
	static assert(false, "Platform not supported");
}


extern(C) void crashSignalHandle(int sig) nothrow @nogc @system{	
	printf("Plugin crash. Signal number: %d.\n",sig);
	thisThreadExit();
}

struct SafeExecutor
{
	alias PluginFunction=void function();
	alias Queue=LowLockQueue!(PluginExecHandle*);

	struct PluginExecHandle{
		PluginFunction fn;
		Condition condition;
		Thread thread;
		bool done=false;
	}

	enum pluginsThreadsNum=10;
	bool exit=false;
	Thread[pluginsThreadsNum] threads;
	Queue queue;

	Semaphore semaphore;

	static void initializeCrashSignalCatching(){
		__gshared bool initialized=false;
		if(initialized){
			return;
		}
		initialized=true;
		//There is no signal function before android api 21
		version(Android){}else{
			signal(SIGABRT,&crashSignalHandle);
			signal(SIGSEGV,&crashSignalHandle);
		}
	}

	void initialize(){
		initializeCrashSignalCatching();
		queue=Mallocator.instance.make!Queue();
		semaphore = Mallocator.instance.make!Semaphore(0);
		foreach(ref th;threads){
			th=Mallocator.instance.make!Thread(&threadMain);
			th.start();
		}
	}

	void end(){
		exit=true;
		foreach(ref th;threads){
			th.join();
			Mallocator.instance.dispose(th);
		}
		Mallocator.instance.dispose(queue);
		Mallocator.instance.dispose(semaphore);
	}

	void renewThread(Thread thread){
		foreach(ref th;threads){
			if(th==thread){
				if(!th.isRunning()){
					Mallocator.instance.dispose(th);
					th=Mallocator.instance.make!Thread(&threadMain);
					th.start();
				}
				break;
			}
		}
	}
	
	bool execute(PluginFunction fn){
		auto mutexScoped=scoped!Mutex();
		Mutex mutex=mutexScoped;
		auto condition=scoped!Condition(mutex);
		PluginExecHandle handle=PluginExecHandle(fn,condition);
		queue.add(&handle);

		auto waitTime=1.msecs;
		synchronized( mutex ){
			semaphore.notify();
			bool ok=handle.condition.wait(waitTime);
			//wait until function ends or thread crashes
			while(!ok){
				if(handle.thread !is null){
					if(handle.thread.isRunning()){
						if(handle.done){
							//Job done
							return true;
						}else{
							//Thread is doing job
							ok=handle.condition.wait(waitTime);
						}
					}else{
						//Thread terminated (crashed)
						renewThread(handle.thread);
						ok=false;
						break;
					}
				}else{
					//Handle is waiting to be cought by some thread
					ok=handle.condition.wait(waitTime);
				}
			}
			return ok;
		}
	}
	
	void threadMain(){
		while(!exit){
			PluginExecHandle* handle=queue.pop;
			if(handle !is null){
				handle.thread=Thread.getThis();
				handle.fn();
				handle.condition.notify();
				handle.done=true;
			}else{
				semaphore.wait(100.msecs);
			}

		}
	}
	
}

