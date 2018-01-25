/**
Module with helper functions for multithreaded modules
 */
module mutils.job_manager.shared_utils;

public import std.experimental.allocator:make,makeArray,dispose;

import core.cpuid : threadsPerCPU;
import mutils.thread: Thread;

import std.conv : to;
import std.experimental.allocator.building_blocks;

public import std.experimental.allocator.mallocator;

//useful for testing if function is safe in multthreated enviroment
//name can be used as id
void testMultithreaded(void delegate() dg, uint threadsCount=0){
	if(threadsCount==0)
		threadsCount=threadsPerCPU;
	Thread[] threadPool=Mallocator.instance.makeArray!(Thread)(threadsCount);
	foreach(i;0..threadsCount){
		//Thread th=Mallocator.instance.make!Thread(func);
		//th.name=i.to!string;//maybe there is better way to pass data to a thread?

		threadPool[i].threadNum=i;
		threadPool[i].setDg(dg);
	}
	foreach(ref thread;threadPool)thread.start();
	foreach(ref thread;threadPool)thread.join();
	Mallocator.instance.dispose(threadPool);	
}
