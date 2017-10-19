module mutils.timeline.trace_bezier;

import std.stdio;

import mutils.container.sorted_vector;
import mutils.container.vector;
import mutils.linalg.algorithm;
import mutils.timeline.utils;

/**
 *
 * Class to get T value interpolated by Bezier Curvein in given time, useful for contigious paths 
 * Class requires at least 3 points to work correctly
 */
struct TraceBezier(T, alias mixFun=mix){
	SortedVector!(DataPoint, "a.time < b.time") data;
	TimeIndexGetter indexGetter;

	struct DataPoint{
		T point;
		T suppVec;
		float time=0;
	}

	void add(T point, float time){
		size_t i=data.add(DataPoint(point,point,time));
	}

	void addAndRecompute(T point, float time){
		size_t i=data.add(DataPoint(point,point,time));
		recompute(i);
	}
	
	void remove(size_t i){
		data.remove(i);
	}
	
	void removeAndRecompute(size_t i){
		data.remove(i);
		if(i!=data.length){
			recompute(i);
		}else{
			recompute(i-1);			
		}
	}
	
	T get(float time){
		uint[2] ti=indexGetter.index(data[], time);
		DataPoint curr=data[ti[0]];
		DataPoint next=data[ti[1]];
		if(ti[0]==ti[1]){
			return curr.point;
		}
		float blend=(time-curr.time)/(next.time-curr.time);
		return mix(curr, next, blend);
	}
	
	void recompute(size_t i){
		if(i==0){
			//data[$-1].suppVec=computeSupportingPoint(data[$-2],data[$-1],data[0]);
			data[0+0].suppVec=computeSupportingPoint(data[0-0],data[0-0],data[1]);
			data[1+0].suppVec=computeSupportingPoint(data[0-0],data[0+1],data[2]);
		}else if(i==1){		
			data[0].suppVec=computeSupportingPoint(data[0],data[0],data[1]);
			data[1].suppVec=computeSupportingPoint(data[0],data[1],data[2]);
			data[2].suppVec=computeSupportingPoint(data[1],data[2],data[3]);
		}else if(i==data.length-1){		
			data[$-2].suppVec=computeSupportingPoint(data[$-3],data[$-2],data[$-1]);
			data[$-1].suppVec=computeSupportingPoint(data[$-2],data[$-1],data[$-1]);
			//data[0-0].suppVec=computeSupportingPoint(data[$-1],data[0+0],data[1-0]);
		}else if(i==data.length-2){		
			data[$-3].suppVec=computeSupportingPoint(data[$-4],data[$-3],data[$-2]);
			data[$-2].suppVec=computeSupportingPoint(data[$-3],data[$-2],data[$-1]);
			data[$-1].suppVec=computeSupportingPoint(data[$-2],data[$-1],data[$-1]);
		}else{
			data[i-1].suppVec=computeSupportingPoint(data[i-2],data[i-1],data[i]);
			data[i+0].suppVec=computeSupportingPoint(data[i-1],data[i],data[i+1]);
			data[i+1].suppVec=computeSupportingPoint(data[i],data[i+1],data[i+2]);
		}		
	}
	
	void computeAll(){
		assert(data.length>=3);
		data[0].suppVec=computeSupportingPoint(data[0],data[0],data[1]);
		foreach(i;1..data.length-1){
			data[i].suppVec=computeSupportingPoint(data[i-1],data[i],data[i+1]);
		}
		data[$-1].suppVec=computeSupportingPoint(data[$-2],data[$-1],data[$-1]);
	}

	float totalLength(){
		return lengthBetween(data[0].time,data[$-1].time, data.length*3);
	}

	float totalTime(){
		return data[$-1].time;
	}

	float lengthBetween(float start, float end, size_t precision){
		T last=get(start);
		float dt=(end-start)/precision;
		float len=0;
		foreach(i;0..precision){
			T p=get(dt*(i+1));
			len+=(p-last).length;
			last=p;
		}
		return len;
	}

	///Normalize time values based on trace width
	void normalizeTime(float end){
		float timPerLen=end/totalLength();
		float start=0;
		data[0].time=start;
		foreach(i,ref p;data[1..$]){
			p.time=lengthBetween(data[0].time,p.time,(i+1)*3)*timPerLen;
		}
	}
//private:

	T computeSupportingPoint(DataPoint prev, DataPoint curr, DataPoint next){
		float ratio=0.25;
		T PN=next.point-prev.point;// Previous Current
		return PN*ratio;
	}

	T mix(DataPoint curr, DataPoint next, float blend){
		T leftSupp=curr.point+curr.suppVec;
		T righSupp=next.point-next.suppVec;
		
		T v1=mixFun(curr.point, leftSupp  , blend);
		T v2=mixFun(leftSupp  , righSupp  , blend);
		T v3=mixFun(righSupp  , next.point, blend);
		T v4=mixFun(v1,v2, blend);
		T v5=mixFun(v2,v3, blend);
		T v6=mixFun(v4,v5, blend);
		return v6;
	}
	bool hasRoundEnds(){
		return data[0].point==data[$-1].point;
	}
	///first and last point should be the same
	void roundEnds(){	
		data[$-1].point=data[0].point;
		data[$-1].suppVec=computeSupportingPoint(data[$-2],data[0+0],data[1]);
		data[0].suppVec=data[$-1].suppVec;
	}

}


unittest{
	import mutils.linalg.vec;
	alias vec=Vec!(float,2);
	alias TraceVec=TraceBezier!(vec);
	TraceVec trace;
	trace.add(vec(0,0),0);
	trace.add(vec(0,1),1);
	trace.add(vec(1,1),2);
	trace.add(vec(1,0),3);
	
	trace.computeAll();	
	trace.addAndRecompute(vec(0.5,1.5),1.5);
}
