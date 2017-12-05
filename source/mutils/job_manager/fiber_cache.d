/**
Containers used to store Fiber objects.
Allocating new Fiber is expensive so need for this containers.
There are few implementations which can be easly changed and tested for performance or correctness.
*/
module mutils.job_manager.fiber_cache;

import core.stdc.stdlib:malloc,free;
import core.stdc.string:memset,memcpy;
import core.atomic;
import core.thread:Fiber,Thread,PAGESIZE;
import core.memory;

import mutils.job_manager.shared_utils;

//only one warning about GC
Fiber newFiber(){
	static void dummy(){}
	Fiber fiber = new Fiber(&dummy,PAGESIZE * 32u);
	GC.addRoot(cast(void*)fiber);	
	fiber.call();
	return fiber;
}

class FiberNoCache{

	Fiber getData(uint,uint){
		Fiber fiber = newFiber();		
		return fiber;
	}

	void removeData(Fiber obj,uint,uint){
		GC.removeRoot(cast(void*)obj);
	}

}

class FiberOneCache{
	static void dummy(){}
	
	static Fiber lastFreeFiber;//1 element tls cache
	
	Fiber getData(uint,uint){
		Fiber fiber;
		if(lastFreeFiber is null){
			fiber = newFiber();
		}else{
			fiber=lastFreeFiber;
			lastFreeFiber=null;
		}
		return fiber;
	}

	void removeData(Fiber obj,uint,uint){
		if(lastFreeFiber !is null){
			GC.removeRoot(cast(void*)lastFreeFiber);
			Mallocator.instance.dispose(lastFreeFiber);
		}
		lastFreeFiber=obj;
	}
}

import mutils.container.vector;
static Vector!Fiber array;
static uint used=0;

void initializeFiberCache(){
	array.reserve(16);
}

class FiberTLSCache{

	this(){}
	
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
			if(obj == fiber){
				array[i]=array[used-1];
				array[used-1]=obj;
				used--;
				return;
			}
		}
		assert(0);
	}
}



