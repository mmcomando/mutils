/**
Module with helper functions for multithreated modules
 */
module mutils.job_manager.shared_utils;

public import std.experimental.allocator:make,makeArray,dispose;

import core.cpuid : threadsPerCPU;
import mutils.thread: Thread;

import std.conv : to;
import std.experimental.allocator.building_blocks;
import std.stdio : writeln,writefln;

public import std.experimental.allocator.mallocator;

//useful for testing if function is safe in multthreated enviroment
//name can be used as id
void testMultithreaded(void delegate() func,uint threadsCount=0){
	if(threadsCount==0)
		threadsCount=threadsPerCPU;
	Thread[] threadPool=Mallocator.instance.makeArray!(Thread)(threadsCount);
	foreach(i;0..threadsCount){
		Thread th=Mallocator.instance.make!Thread(func);
		th.name=i.to!string;//maybe there is better way to pass data to a thread?
		threadPool[i]=th;
	}
	foreach(thread;threadPool)thread.start();
	foreach(thread;threadPool)thread.join();
	foreach(thread;threadPool)Mallocator.instance.dispose(thread);
	Mallocator.instance.dispose(threadPool);	
}
