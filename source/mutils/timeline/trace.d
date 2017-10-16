module mutils.timeline.trace;

import std.stdio;

import mutils.container.sorted_vector;
import mutils.container.vector;
import mutils.linalg.algorithm;

/**
 *
 * Class to get interpolated(mix) T value in given time, useful for contigious paths 
 * 
 */
struct Trace(T, alias mixFunction=mix){
	SortedVector!(DataPoint,"a.time < b.time") data;
	uint lastNum=0;

	struct DataPoint{
		T point;
		float time=0;
	}

	void add(T point, float time){
		data~=DataPoint(point,time);
	}
	
	void remove(size_t i){
		data.remove(i);
	}
	
	T get(float time){
		assert(data.length>lastNum);
		if(time<data[0].time){
			return data[0].point;
		}
		foreach(i;1..data.length){
			DataPoint last=data[i-1];
			if(time>=last.time && time <=data[i].time){
				float blend=(time-last.time)/(data[i].time-last.time);
				return mixFunction(last.point,data[i].point,blend);
			}
		}
		return data[$-1].point;
	}

	T getCached(float time){
		assert(data.length>lastNum);
		if(time<data[lastNum].time){
			lastNum=0;
			return data[lastNum].point;
		}
		if(time<data[0].time){
			lastNum=0;
			return data[0].point;
		}
		foreach(i;lastNum+1..data.length){
			DataPoint last=data[i-1];
			if(time>=last.time && time <=data[i].time){
				lastNum=cast(uint)i;
				float blend=(time-last.time)/(data[i].time-last.time);
				assert(get(time)==mixFunction(last.point, data[i].point, blend));
				return mixFunction(last.point, data[i].point, blend);
			}
		}
		lastNum=cast(uint)data.length-1;
		return data[$-1].point;
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

	assert(trace.getCached(-10)==vec2i(0,0));
	assert(trace.getCached(0)==vec2i(0,0));
	assert(trace.getCached(1)==vec2i(2,2));
	assert(trace.getCached(2.5)==vec2i(1,1));
	assert(trace.getCached(5)==vec2i(2,2));
	assert(trace.getCached(-10)==vec2i(0,0));
	assert(trace.getCached(0)==vec2i(0,0));	
}

