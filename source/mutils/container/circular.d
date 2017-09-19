module mutils.container.circular;

struct Circular(T){
	T[] range;
	size_t currElement;

	this(T[] r){
		assert(r.length>0);
		range=r;
	}

	ref T get(){
		return range[currElement];
	}

	ref T popFront(){
		currElement++;
		if(currElement>=range.length){
			currElement=0;
		}
		return get();
	}

	ref T popBack(){
		if(currElement==0){
			currElement=range.length;
		}
		currElement--;
		return get();
	}

}

