/**
Module with queue
 */
module mutils.container_shared.shared_queue;

import core.atomic;
import std.experimental.allocator;
import std.experimental.allocator.building_blocks.bitmapped_block : SharedBitmappedBlock;
import std.experimental.allocator.common : platformAlignment;
import std.experimental.allocator.mallocator : Mallocator;
import std.typecons : Flag, Yes, No;

import mutils.thread;

struct MyMallocator {
	@disable this(this);

	auto make(T, Args...)(auto ref Args args) {
		return Mallocator.instance.make!T(args);
	}

	void dispose(T)(ref T* obj) {
		Mallocator.instance.dispose(obj);
	}
}

struct LowLockQueue(T, CType = int) {
	@disable this(this);
private:
	static struct Node {
		this(T val) {
			value = val;
		}

		T value;
		align(64) Node* next; //atomic
	};

	// for one consumer at a time
	align(64) Node* first;
	// shared among consumers
	//MutexSpinLock  Mutex consumerLock;
	MutexSpinLock consumerLock;

	// for one producer at a time
	align(64) Node* last;
	// shared among producers
	MutexSpinLock producerLock;


	alias Allocator = SharedBitmappedBlock!(Node.sizeof, platformAlignment,
			Mallocator, No.multiblock);

	Allocator* allocator;

public:
	void initialize() {
		allocator = new Allocator(1024 * 1024 * 1024);
		first = allocator.make!(Node)(T.init);
		last = first;
		consumerLock.initialzie();
		producerLock.initialzie();
	}

	void clear() {
		assert(empty == true);
	}

	~this() {
		clear();
	}

	bool empty() {
		bool isEmpty;
		//consumerLock.lock();
		isEmpty = first.next == null;
		//consumerLock.unlock();
		return isEmpty;
	}

	void add(T t) {
		Node* tmp = allocator.make!(Node)(t);

		producerLock.lock();
		last.next = tmp;
		last = tmp;
		producerLock.unlock();
	}

	void add(T[] t) {
		if (t.length == 0) {
			return;
		}
		Node* firstInChain;
		Node* lastInChain;
		Node* tmp = allocator.make!(Node)(t[0]);
		firstInChain = tmp;
		lastInChain = tmp;
		foreach (n; 1 .. t.length) {
			tmp = allocator.make!(Node)(t[n]);
			lastInChain.next = tmp;
			lastInChain = tmp;
		}

		producerLock.lock();
		last.next = firstInChain;
		last = lastInChain;
		producerLock.unlock();

	}

	T pop() {
		consumerLock.lock();

		T varInit;
		Node* theFirst = first;
		Node* theNext = first.next;
		if (theNext != null) {
			T result = theNext.value;
			theNext.value = varInit;
			first = theNext;
			consumerLock.unlock();

			allocator.dispose(theFirst);
			return result;
		}

		consumerLock.unlock();
		return varInit;
	}

	T tryPop() {
		T varInit;
		bool locked = consumerLock.tryLock();
		if (locked == false) {
			return varInit;
		}

		Node* theFirst = first;
		Node* theNext = first.next;
		if (theNext != null) {
			T result = theNext.value;
			theNext.value = varInit;
			first = theNext;
			consumerLock.unlock();

			allocator.dispose(theFirst);
			return result;
		}

		consumerLock.unlock();
		return varInit;
	}
}
