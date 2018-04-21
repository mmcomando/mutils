/**
Module with queue
 */
module mutils.container_shared.shared_queue;

import core.atomic;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;

struct MyMallocator{
	@disable this(this);
	
	auto make(T,Args...)(auto ref Args args){
		return Mallocator.instance.make!T(args);
	}
	void dispose(T)(ref T* obj){
		Mallocator.instance.dispose(obj);
	}
}

//algorithm from  http://collaboration.cmc.ec.gc.ca/science/rpn/biblio/ddj/Website/articles/DDJ/2008/0811/081001hs01/081001hs01.html
//By Herb Sutter

//Maybe the fastest for not contested resource
struct LowLockQueue(T) {
	@disable this(this);
private:
	static struct Node {
		this( T val )  {			
			value=val;
		}
		T value;
		align (64)  Node* next;//atomic
	};
	
	shared uint elementsAdded;
	shared uint elementsPopped;
	// for one consumer at a time
	align (64)  Node* first;
	// shared among consumers
	MutexSpinLock consumerLock;
	
	// for one producer at a time
	align (64)  Node* last; 
	// shared among producers
	MutexSpinLock producerLock;
	
	
	//alias Allocator=BucketAllocator!(Node.sizeof);
	alias Allocator=MyMallocator;
	Allocator allocator;
	
public:
	void initialize(){
		first = last =  allocator.make!(Node)( T.init );		
		consumerLock.initialzie();
		producerLock.initialzie();
	}

	void clear(){
		assert(empty==true);
	}

	~this(){
		clear();
	}
	
	
	bool empty(){
		bool isEmpty;
		consumerLock.lock();
		isEmpty=first.next == null; 
		consumerLock.unlock();
		return isEmpty;
	}

	void add( T  t ) {
		Node* tmp = allocator.make!(Node)( t );

		producerLock.lock();
		last.next = tmp;
		last = tmp;
		producerLock.unlock();
		atomicOp!"+="(elementsAdded,1);
		
	}
	void add( T[]  t ) {
		if(t.length==0){
			return;
		}
		Node* firstInChain;
		Node* lastInChain;
		Node* tmp = allocator.make!(Node)( t[0] );
		firstInChain=tmp;
		lastInChain=tmp;
		foreach(n;1..t.length){
			tmp = allocator.make!(Node)( t[n] );
			lastInChain.next=tmp;
			lastInChain=tmp;
		}

		producerLock.lock();
		last.next = firstInChain;
		last = lastInChain;	
		producerLock.unlock();
		atomicOp!"+="(elementsAdded,t.length);
		
	}
	
	
	
	T pop(  ) {
		consumerLock.lock();
		
		T varInit;
		Node* theFirst = first;
		Node* theNext = first.next;
		if( theNext != null ) {
			T result = theNext.value;
			theNext.value = varInit;
			first = theNext;
			consumerLock.unlock();
			atomicOp!"+="(elementsPopped,1);
			
			allocator.dispose(theFirst);
			return result;
		}

		consumerLock.unlock();
		return varInit;
	}
}


