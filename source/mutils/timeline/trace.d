module mutils.timeline.trace;

import mutils.container.sorted_vector;
import mutils.container.vector;
import mutils.linalg.algorithm;
import mutils.timeline.utils;

/**
 *
 * Class to get interpolated(mix) T value in given time, useful for contigious paths 
 * 
 */
struct Trace(T, alias mixFunction=mix){
	SortedVector!(DataPoint, "a.time < b.time") data;
	TimeIndexGetter indexGetter;

	struct DataPoint{
		T point;
		float time=0;
	}

	void add(T point, float time){
		data~=DataPoint(point, time);
	}
	
	void remove(size_t i){
		data.remove(i);
	}
	
	T get(float time){
		uint[2] ti=indexGetter.index(data[], time);
		DataPoint curr=data[ti[0]];
		DataPoint next=data[ti[1]];
		if(ti[0]==ti[1]){
			return curr.point;
		}
		float blend=(time-curr.time)/(next.time-curr.time);
		return mixFunction(curr.point, next.point, blend);
	}


}


unittest{
	import mutils.linalg.vec;
	alias vec2i=Vec!(int,2);//ints because there are no precision errors
	alias TraceVec2i=Trace!(vec2i);
	TraceVec2i trace;
	trace.add(vec2i(0,0),0);
	trace.add(vec2i(0,0),2);
	trace.add(vec2i(2,2),1);
	trace.add(vec2i(2,2),3);

	assert(trace.data[2].point==vec2i(0,0));

	assert(trace.get(-10)==vec2i(0,0));
	assert(trace.get(0)==vec2i(0,0));
	assert(trace.get(1)==vec2i(2,2));
	assert(trace.get(2.5)==vec2i(1,1));
	assert(trace.get(5)==vec2i(2,2));
	assert(trace.get(-10)==vec2i(0,0));
	assert(trace.get(0)==vec2i(0,0));	
}

