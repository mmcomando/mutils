module mutils.timeline.utils;


import std.traits;



struct TimeIndexGetter{
	uint lastIndex=0;
	float lastTime=0;
	
	uint[2] index(T)(in T[] slice, float time) {
		static assert(hasMember!(T, "time"));
		assert(slice.length<lastIndex.max);
		assert(slice.length>0);
		if(lastIndex>=slice.length || lastTime>time){
			lastIndex=0;
		}
		
		lastTime=time;
		
		uint[2] ti;
		if(time<slice[0].time){
			lastIndex=0;
			return ti;
		}
		foreach(uint i; lastIndex+1..cast(uint)slice.length){
			if(time<slice[i].time){
				ti[0]=i-1;
				ti[1]=i;
				lastIndex=i-1;
				return ti;
			}
			
		}
		lastIndex=cast(uint)slice.length-2;
		uint last=cast(uint)(slice.length-1);
		ti[0]=last;
		ti[1]=last;
		return ti;
	}
}