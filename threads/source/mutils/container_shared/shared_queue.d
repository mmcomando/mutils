/**
Module with queue
 */
module mutils.container_shared.shared_queue;

import core.atomic;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;

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

//algorithm from  http://collaboration.cmc.ec.gc.ca/science/rpn/biblio/ddj/Website/articles/DDJ/2008/0811/081001hs01/081001hs01.html
//By Herb Sutter

//Maybe the fastest for not contested resource
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

	shared uint elementsAdded;
	shared uint elementsPopped;
	// for one consumer at a time
	align(64) Node* first;
	// shared among consumers
	//MutexSpinLock  Mutex consumerLock;
	MutexSpinLock consumerLock;

	// for one producer at a time
	align(64) Node* last;
	// shared among producers
	MutexSpinLock producerLock;

	//alias Allocator=BucketAllocator!(Node.sizeof);
	//alias Allocator = MyMallocator;
	//Allocator allocator;

	import std.experimental.allocator.building_blocks.bitmapped_block : SharedBitmappedBlock;
	import std.experimental.allocator.mallocator : Mallocator;
	import std.experimental.allocator.common : platformAlignment;
import std.typecons : Flag, Yes, No;

	enum blockSize = Node.sizeof;
	//pragma(msg, blockSize);
	//pragma(msg, platformAlignment);
	alias Allocator = SharedBitmappedBlock!(blockSize, platformAlignment,
			Mallocator, No.multiblock);

	Allocator* allocator;
import std.stdio;
public:
	void initialize() {
		allocator=new Allocator(1024*1024*1024);
		//writeln(T.sizeof);
		//writeln(first, " ", last);
		first =  allocator.make!(Node)(T.init);
		last = first;
		//writeln(first, " ", last);
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
		//writeln(tmp);

		producerLock.lock();
		last.next = tmp;
		last = tmp;
		producerLock.unlock();
		//atomicOp!"+="(elementsAdded,1);

	}

	void add(T[] t) {
		if (t.length == 0) {
			return;
		}
		Node* firstInChain;
		Node* lastInChain;
		Node* tmp = allocator.make!(Node)(t[0]);
		//writeln(tmp);
		firstInChain = tmp;
		lastInChain = tmp;
		foreach (n; 1 .. t.length) {
			tmp = allocator.make!(Node)(t[n]);
		//writeln(tmp);
			lastInChain.next = tmp;
			lastInChain = tmp;
		}

		producerLock.lock();
		last.next = firstInChain;
		last = lastInChain;
		producerLock.unlock();
		//atomicOp!"+="(elementsAdded,t.length);

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
			//atomicOp!"+="(elementsPopped,1);

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
			//atomicOp!"+="(elementsPopped,1);

			allocator.dispose(theFirst);
			return result;
		}

		consumerLock.unlock();
		return varInit;
	}
}
