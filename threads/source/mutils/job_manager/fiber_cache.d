/**
Containers used to store Fiber objects.
Allocating new Fiber is expensive so need for this containers.
There are few implementations which can be easly changed and tested for performance or correctness.
*/
module mutils.job_manager.fiber_cache;

import core.atomic;
import core.memory;
import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy, memset;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;

import mutils.container.vector;
import mutils.job_manager.manager_utils;
import mutils.thread : Fiber, PAGESIZE, Thread;

//only one warning about GC
Fiber newFiber() {
	Fiber fiber = Mallocator.instance.make!(Fiber)(PAGESIZE * 64);
	fiber.state = Fiber.State.TERM;
	return fiber;
}

struct FiberTLSCache {

	align(64) Vector!Fiber array;
	align(64) uint used = 0;

	void clear() {
		array.clear();
		used = 0;
	}

	Fiber getData() {
		Fiber fiber;
		if (array.length <= used) {
			fiber = newFiber();
			array ~= fiber;
			used++;
			return fiber;
		}
		fiber = array[used];
		used++;
		return fiber;
	}

	void removeData(Fiber obj) {
		foreach (i, fiber; array) {
			if (cast(void*) obj == cast(void*) fiber) {
				array[i] = array[used - 1];
				array[used - 1] = obj;
				used--;
				return;
			}
		}
		assert(0);
	}
}
