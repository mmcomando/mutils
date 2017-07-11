/**
Module with queue
 */
module mutils.job_manager.shared_queue;

import core.atomic;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;

import mutils.job_manager.shared_allocator;
//algorithm from  http://collaboration.cmc.ec.gc.ca/science/rpn/biblio/ddj/Website/articles/DDJ/2008/0811/081001hs01/081001hs01.html
//By Herb Sutter

//Maybe the fastest for not contested resource
//lock type is mainly used to distinguish operations in profiler (different function names if not inlined)
class LowLockQueue(T,LockType=bool) {
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
	align (64) shared LockType consumerLock;
	
	// for one producer at a time
	align (64)  Node* last; 
	// shared among producers
	align (64) shared LockType producerLock;//atomic
	
	
	alias Allocator=BucketAllocator!(Node.sizeof);
	//alias Allocator=MyMallcoator;
	//alias Allocator=MyGcAllcoator;
	Allocator allocator;
	
public:
	this() {
		allocator=Mallocator.instance.make!Allocator();
		first = last =  allocator.make!(Node)( T.init );		
		producerLock = consumerLock = false;
	}
	~this(){
		Mallocator.instance.dispose(allocator);
	}
	
	
	bool empty(){
		return (first.next == null); 
	}

	void add( T  t ) {
		Node* tmp = allocator.make!(Node)( t );
		while( !cas(&producerLock,cast(LockType)false,cast(LockType)true )){ } 	// acquire exclusivity
		last.next = tmp;		 		// publish to consumers
		last = tmp;		 		// swing last forward
		atomicStore(producerLock,false);		// release exclusivity
		atomicOp!"+="(elementsAdded,1);
		
	}
	void add( T[]  t ) {
		
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
		while( !cas(&producerLock,cast(LockType)false,cast(LockType)true )){ } 	// acquire exclusivity
		last.next = firstInChain;		 		// publish to consumers
		last = lastInChain;		 		// swing last forward
		atomicStore(producerLock,cast(LockType)false);		// release exclusivity
		atomicOp!"+="(elementsAdded,t.length);
		
	}
	
	
	
	T pop(  ) {
		while( !cas(&consumerLock,cast(LockType)false,cast(LockType)true ) ) { }	 // acquire exclusivity
		
		
		Node* theFirst = first;
		Node* theNext = first.next;
		if( theNext != null ) { // if queue is nonempty
			T result = theNext.value;	 	       	// take it out
			theNext.value = T.init; 	       	// of the Node
			first = theNext;		 	       	// swing first forward
			atomicStore(consumerLock,cast(LockType)false);	       	// release exclusivity		
			atomicOp!"+="(elementsPopped,1);
			
			allocator.dispose(theFirst);
			return result;	 		// and report success
		}
		
		atomicStore(consumerLock,cast(LockType)false);       	// release exclusivity
		return T.init; 	// report queue was empty
	}
}

void testLLQ(){
	import mutils.job_manager.shared_utils;
	import std.random:uniform;
	import std.functional:toDelegate;
	static int[] tmpArr=[1,1,1,1,1,1];
	static shared uint addedElements;
	__gshared LowLockQueue!int queue;
	queue=Mallocator.instance.make!(LowLockQueue!int);
	scope(exit)Mallocator.instance.dispose(queue);
	
	static void testLLQAdd(){
		uint popped;
		foreach(kk;0..1000){
			uint num=uniform(0,1000);
			atomicOp!"+="(addedElements,num+num*6);
			foreach(i;0..num)queue.add(1);
			foreach(i;0..num)queue.add(tmpArr);
			foreach(i;0..num+num*6){
				popped=queue.pop();
				assert(popped==1);
			}
		}
	}
	testMultithreaded((&testLLQAdd).toDelegate,4);
	assert(queue.elementsAdded==addedElements);
	assert(queue.elementsAdded==queue.elementsPopped);
	assert(queue.first.next==null);
	assert(queue.first==queue.last);
}
