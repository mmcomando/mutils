/**
Module with helper functions for multithreaded modules
 */
module mutils.job_manager.shared_utils;

import core.cpuid : threadsPerCPU;
import std.conv : to;
import std.experimental.allocator : dispose, make, makeArray;
import std.experimental.allocator.building_blocks;
import std.experimental.allocator.mallocator;

import mutils.thread : Thread;

//useful for testing if function is safe in multthreated enviroment
//name can be used as id
void testMultithreaded(void delegate() dg, uint threadsCount = 0) {
	if (threadsCount == 0)
		threadsCount = threadsPerCPU;
	Thread[] threadPool = Mallocator.instance.makeArray!(Thread)(threadsCount);
	foreach (i; 0 .. threadsCount) {
		//Thread th=Mallocator.instance.make!Thread(func);
		//th.name=i.to!string;//maybe there is better way to pass data to a thread?

		threadPool[i].threadNum = i;
		threadPool[i].setDg(dg);
	}
	foreach (ref thread; threadPool)
		thread.start();
	foreach (ref thread; threadPool)
		thread.join();
	Mallocator.instance.dispose(threadPool);
}
