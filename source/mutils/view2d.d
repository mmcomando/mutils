module mutils.view2d;

import std.traits: ForeachType;

struct View2D(Slice){
	alias T=ForeachType!Slice;
	Slice slice;
	size_t columnsNum=1;
	
	
	Slice opIndex(size_t y){
		return slice[y*columnsNum..(y+1)*columnsNum];
	}

	ref T opIndex(size_t y, size_t x){
		assert(x<columnsNum);
		return slice[y*columnsNum+x];
	}

	Slice opIndex(size_t y, size_t[2] x){
		assert(x[0]<=x[1]);
		assert(x[1]<=columnsNum);
		size_t start=y*columnsNum;
		return slice[start+x[0]..start+x[1]];
	}

	size_t[2] opSlice(size_t dim)(size_t start, size_t end){
		return [start, end];
	}

	size_t opDollar(size_t dim )() { 
		static assert(dim<2);
		static if(dim==0){
			return columnsNum; 
		}else{
			return cast(size_t)(slice.length/columnsNum);
		}
	}

	// foreach support
	int opApply(scope int delegate(Slice) dg){ 
		int result;
		foreach(y;0..cast(size_t)(slice.length/columnsNum)){			
			result=dg(opIndex(y));
			if (result)
				break;	
		}		
		
		return result;
	}

	// foreach support
	int opApply(scope int delegate(size_t, Slice) dg){ 
		int result;
		foreach(y;0..cast(size_t)(slice.length/columnsNum)){			
			result=dg(y, opIndex(y));
			if (result)
				break;	
		}		
		
		return result;
	}
}

unittest{
	int[9] arr=[0,1,2,3,4,5,6,7,8];
	View2D!(int[]) view;
	view.slice=arr[];
	view.columnsNum=3;
	
	// opIndex[y]
	assert(view[0]==[0,1,2]);
	assert(view[1]==[3,4,5]);
	assert(view[2]==[6,7,8]);
	
	// opIndex[y, x]
	assert(view[0,0]==0);
	assert(view[0,1]==1);
	assert(view[0,2]==2);
	assert(view[1,0]==3);
	assert(view[1,1]==4);
	assert(view[1,2]==5);
	assert(view[2,0]==6);
	assert(view[2,1]==7);
	assert(view[2,2]==8);
	// opIndex[y,x1..x2]
	assert(view[0,1..$]==[1,2]);
	// opDollar
	assert(view[$-1]==[6,7,8]);
	assert(view[$-1,$-2]==7);
	// Foreach
	foreach(row; view){}
	foreach(i, row; view){
		assert(row==[i*3+0, i*3+1, i*3+2]);
	}
	// Assigment
	view[2,2]=123;
	assert(view[2,2]==123);
}