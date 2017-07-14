module mutils.container.buckets_chain;

import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.stdio;
import std.traits;

import mutils.container.vector;

enum doNotInline="pragma(inline,false);version(LDC)pragma(LDC_never_inline);";


struct BitsArray(uint bitsNum){
	ubyte[bitsNum/8+(bitsNum%8>0)+0] bytes;

	static uint byteNumber(uint bitNum){
		return bitNum/8;
	}
	void set(uint bitNum){
		assert(bitNum<bitsNum);
		uint byteNum=byteNumber(bitNum);
		uint bitInByte=bitNum%8;
		bytes[byteNum] |= 1 << bitInByte;
	
	}
	void clear(uint bitNum){
		assert(bitNum<bitsNum);
		uint byteNum=byteNumber(bitNum);
		uint bitInByte=bitNum%8;
		bytes[byteNum] &= ~(1 << bitInByte);
	}

	bool get(uint bitNum){
		assert(bitNum<bitsNum);
		uint byteNum=byteNumber(bitNum);
		uint bitInByte=bitNum%8;
		return (bytes[byteNum] >> bitInByte) & 1;
	}
	uint numOfSetBits(){
		uint num;
		foreach(uint i;0..bitsNum){
			num+=get(i);
		}
		return num;
	}
}

unittest{
	alias BA=BitsArray!(13);
	BA ba;

	assert(ba.bytes.length==2);
	ba.set(0);
	ba.set(1);
	ba.set(8);
	ba.set(9);
	assert(ba.bytes[0]==3);
	assert(ba.bytes[1]==3);
	ba.clear(1);
	ba.clear(9);
	assert(ba.bytes[0]==1);
	assert(ba.bytes[1]==1);
}
/**
 * Value typed fixed size container.
 * It is not random access container.
 * Empty elements are determined by bitfields.
 * Designed to be performant when iterating on all elements. If container is full simple foreach is used.
 */
struct BucketWithBits(T,uint elementsNum=128){
	static assert(elementsNum%8==0,"Number of elements must be multiple of 8.");
	T[elementsNum] elements;
	BitsArray!(elementsNum) emptyElements;

	void initialize(){
		clear();
	}

	void clear(){
		foreach(ref T el;this){
			remove(&el);
		}
		assert(length==0);
		foreach(uint i;0..elementsNum){
			emptyElements.set(i);
		}
	}

	size_t length(){
		return elementsNum-emptyElements.numOfSetBits;
	}

	private int getEmptyElementNum(){
		int num=-1;
	upper:foreach(uint i,b;emptyElements.bytes){
			if(b>0){
				foreach(uint j;0..8){
					if(emptyElements.get(i*8+j)){
						num=i*8+j;
						emptyElements.clear(num);
						break upper;
					}
				}
			}
		}
		return num;
	}

	T* add(){
		int num=getEmptyElementNum();	
		assert(num!=-1);

		elements[num]=T.init;

		return &elements[num];
	}
	static if(isImplicitlyConvertible!(T, T)){// @disable this(this) don't support this type of add
		T* add(ref T obj){
			int num=getEmptyElementNum();
			assert(num!=-1);

			elements[num]=obj;
			return &elements[num];
		}

		T* add(T obj){
			return add(obj);
		}
	}

	void opOpAssign(string op)(T obj){
		static assert(op=="~");
		add(obj);
	}

	void opOpAssign(string op)(T[] obj){
		static assert(op=="~");
		foreach(o;obj){
			add(obj);
		}
	}

	bool isFull(){
		foreach(b;emptyElements.bytes){
			if(b!=0){
				return false;
			}
		}
		return true;
	}

	void remove(T* obj){
		sizediff_t dt=cast(void*)obj-cast(void*)&elements[0];
		uint num=cast(uint)(dt/T.sizeof);
		assert(num<elementsNum);
		emptyElements.set(num);

		destroy(*obj);

		elements[num]=T.init;
	}

	bool isIn(T* obj){
		size_t ptr=cast(size_t)obj;
		size_t ptrBeg=cast(size_t)&elements;
		size_t ptrEnd=cast(size_t)&elements[elementsNum-1];
		if(ptr>=ptrBeg && ptr<=ptrEnd){
			return true;
		}
		return false;
	}

	int opApply(Dg)(scope Dg dg)
	{ 
		static assert (ParameterTypeTuple!Dg.length == 1 || ParameterTypeTuple!Dg.length == 2);
		enum hasI=ParameterTypeTuple!Dg.length == 2;
		static if(hasI){
			alias IType=ParameterTypeTuple!Dg[0];
			IType index=0;
		}

		int result;
		if(isFull()){
			foreach(int i,ref el;elements){
				static if(hasI){
					result=dg(i,el);
				}else{
					result=dg(el);
				}
				if (result)
					break;			
			}
		}else{
			//the code is faster when this pice code is inner function
			//probably because rare executing code is not inlined (less code in main execution path)
			void byElementIteration(){
				mixin(doNotInline);
			upper:foreach(int k,b;emptyElements.bytes){
					if(b==0){
						foreach(int i,ref el;elements[k*8..k*8+8]){
							static if(hasI){
								result=dg(index,el);
								index++;
							}else{
								result=dg(el);
							}
							if (result)
								break upper;
						}
					} else {
						foreach(uint i;0..8){
							if(emptyElements.get(k*8+i)==false){
								static if(hasI){
									result=dg(index, elements[k*8+i]);
									index++;
								}else{
									result=dg(elements[k*8+i]);
								}
								if (result)
									break upper;
							}
						}
					}
				}
			}
			byElementIteration();
		}

		return result;
	}
}

unittest{
	alias WWWW=BucketWithBits!(long,16);
	WWWW bucket;
	bucket.initialize();
	assert(bucket.length==0);

	long* ptr;
	ptr=bucket.add(0);
	ptr=bucket.add(1);
	ptr=bucket.add(1);
	assert(bucket.isIn(ptr));
	bucket.add(2);
	bucket.add(3);
	bucket.remove(ptr);
	assert(bucket.length==4);
	foreach(int i,ref long el;bucket){
		assert(i==el);
		bucket.remove(&el);
	}
	assert(bucket.length==0);
	//test one byte full
	bucket.clear();
	assert(bucket.length==0);
	foreach(i;0..12){
		bucket.add(11);
	}
	foreach(int i,long el;bucket){
		assert(el==11);
	}
	//test all used
	bucket.clear();
	assert(bucket.length==0);
	foreach(i;0..16){
		bucket.add(15);
	}
	foreach(int i,long el;bucket){
		assert(el==15);
	}
}

/**
 * Not relocating container.
 * Designed for storing a lot of objects in contiguous memory and iterating over them without performance loss.
 * Adding and removing elements is slow (linear).
 */
struct BucketsChain(T, uint elementsInBucket=64, bool addGCRange=hasIndirections!T){
	alias ElementType=T;
	alias MyBucket=BucketWithBits!(T,elementsInBucket);
	Vector!(MyBucket*) buckets;

	@disable this(this);

	void initialize(){
		//buckets=Mallocator.instance.make!(Vector!(MyBucket*));
	}

	void clear(){
		foreach(b;buckets){
			b.clear();
		}
	}

	MyBucket* addBucket(){
		MyBucket* b=Mallocator.instance.make!MyBucket;
		b.initialize();
		static if(addGCRange){
			import core.memory;
			GC.addRange(b.elements.ptr,b.elements.length*T.sizeof);
		}
		buckets~=b;
		return b;
	}

	size_t length(){
		size_t len;
		foreach(b;buckets){
			len+=b.length;
		}
		return len;
	}

	private MyBucket* getFreeBucket(){
		MyBucket* bucket;
		foreach(b;buckets){
			if(!b.isFull){
				bucket=b;
				break;
			}
		}
		if(bucket is null){
			bucket=addBucket();
		}

		return bucket;
	}

	T* add(){		
		return getFreeBucket.add();
	}


	static if(isImplicitlyConvertible!(T, T)){// @disable this(this) don't support this type of add
		T* add(T obj){
			return getFreeBucket().add(obj);
		}
	}

	void opOpAssign(string op)(T obj){
		static assert(op=="~");
		add(obj);
	}
	
	void opOpAssign(string op)(T[] obj){
		static assert(op=="~");
		foreach(o;obj){
			add(obj);
		}
	}

	void remove(T* obj){
		foreach(b;buckets){
			if(b.isIn(obj)){
				b.remove(obj);
				return;
			}
		}
		writeln("---");
		writeln(obj);
		writeln();
		foreach(b;buckets){
			writeln();
			writeln(b.elements.ptr);
			writeln(&b.elements[$-1]);

		}
		assert(0);
	}



	int opApply(Dg)(scope Dg dg)
	{ 
		static assert (ParameterTypeTuple!Dg.length == 1 || ParameterTypeTuple!Dg.length == 2);
		enum hasI=ParameterTypeTuple!Dg.length == 2;
		static if(hasI){
			alias IType=ParameterTypeTuple!Dg[0];
			IType index=0;
		}
		
		int result;
		foreach(bucket;buckets){
			foreach(ref T el;*bucket){
				static if(hasI){
					result=dg(index,el);
					index++;
				}else{
					result=dg(el);
				}
			if (result)
				break;			
			}
		
		}
		return result;
	}
}

unittest{
	BucketsChain!(long,16) vec;
	vec.initialize();
	long* ptr;
	ptr=vec.add(1);
	foreach(i;0..100){
		vec.add(2);
	}
	assert(ptr==&vec.buckets[0].elements[0]);
	vec.remove(ptr);
	ptr=vec.add(1);
	assert(ptr==&vec.buckets[0].elements[0]);
	vec.remove(ptr);

	foreach(int i,ref long el;vec){
		assert(el==2);
	}
	foreach(int i,ref long el;vec){
		vec.remove(&el);
	}
	assert(vec.length==0);
}







struct BucketWithList(T,uint elementsNum=128){
	union Element{
		Element* next;
		T obj;
	}
	Element[elementsNum] elements;
	Element* emptyOne;
	
	void initialize(){
		foreach(i,ref el;elements[0..elementsNum-1]){
			el.next=&elements[i+1];
		}
		elements[elementsNum-1].next=null;
		emptyOne=&elements[0];
	}
	
	void clear(){
		initialize();
	}

	T* add(){
		assert(emptyOne !is null);
		Element* el=emptyOne;
		emptyOne=el.next;
		el.obj=T.init;
		return &el.obj;
	}
	
	T* add(T obj){
		assert(emptyOne !is null);
		Element* el=emptyOne;
		emptyOne=el.next;
		el.obj=obj;
		return &el.obj;
	}

	void remove(T* obj){
		Element* el=cast(Element*)obj;
		el.next=emptyOne;
		emptyOne=el;
	}

	bool isIn(T* obj){
		size_t ptr=cast(size_t)obj;
		size_t ptrBeg=cast(size_t)&elements[0];
		size_t ptrEnd=cast(size_t)&elements[elementsNum-1];
		if(ptr>=ptrBeg && ptr<=ptrEnd){
			return true;
		}
		return false;
	}

	bool isFull(){
		return emptyOne is null;
	}
}



struct BucketsListChain(T, uint elementsInBucket=64, bool addGCRange=hasIndirections!T){
	alias ElementType=T;
	alias MyBucket=BucketWithList!(T,elementsInBucket);
	Vector!(MyBucket*) buckets;
	
	@disable this(this);
	
	void initialize(){}
	
	void clear(){
		foreach(b;buckets){
			b.clear();
		}
	}

	
	MyBucket* addBucket(){
		MyBucket* b=Mallocator.instance.make!MyBucket;
		b.initialize();
		static if(addGCRange){
			import core.memory;
			GC.addRange(b.elements.ptr,b.elements.length*T.sizeof);
		}
		buckets~=b;
		return b;
	}

	
	private MyBucket* getFreeBucket(){
		MyBucket* bucket;
		foreach(b;buckets){
			if(!b.isFull){
				bucket=b;
				break;
			}
		}
		if(bucket is null){
			bucket=addBucket();
		}
		
		return bucket;
	}
	
	T* add(){		
		return getFreeBucket.add();
	}
	
	
	static if(isImplicitlyConvertible!(T, T)){// @disable this(this) -  don't support this type of add
		T* add(T obj){
			return getFreeBucket().add(obj);
		}
	}

	
	void remove(T* obj){
		foreach(b;buckets){
			if(b.isIn(obj)){
				b.remove(obj);
				return;
			}
		}
		assert(0);
	}
}