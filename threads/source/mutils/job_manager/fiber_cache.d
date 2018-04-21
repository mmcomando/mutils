/**
Containers used to store Fiber objects.
Allocating new Fiber is expensive so need for this containers.
There are few implementations which can be easly changed and tested for performance or correctness.
*/
module mutils.job_manager.fiber_cache;

import core.stdc.stdlib:malloc,free;
import core.stdc.string:memset,memcpy;
import core.atomic;
import mutils.thread: Fiber, Thread, PAGESIZE;
import mutils.container.vector;
import mutils.job_manager.manager_utils;
import core.memory;


import std.experimental.allocator;
import std.experimental.allocator.mallocator;
//only one warning about GC
Fiber newFiber(){
	Fiber fiber = Mallocator.instance.make!(Fiber)(PAGESIZE * 32u);
	fiber.state=Fiber.State.TERM;
	return fiber;
}



Vector!Fiber array;
uint used=0;

struct FiberTLSCache{	
	
	void clear(){
		array.clear();
		used=0;
	}

	Fiber getData(uint,uint){
		Fiber fiber;
		if(array.length<=used){
			fiber= newFiber();
			array~=fiber;
			used++;
			return fiber;
		}
		fiber=array[used];
		used++;
		return fiber;
	}

	void removeData(Fiber obj,uint,uint){
		foreach(i,fiber;array){
			if(cast(void*)obj == cast(void*)fiber){
				array[i]=array[used-1];
				array[used-1]=obj;
				used--;
				return;
			}
		}
		assert(0);
	}
}



