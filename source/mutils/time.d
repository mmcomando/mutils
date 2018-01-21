module mutils.time;

import core.sys.windows.windows;
import core.sys.posix.sys.time;



// Replacement for deprecated std.datetime StopWatch, used mainly in benchmark tests
struct StopWatch{
	long begin;
	long end;
	
	void start(){
		begin=useconds();
	}
	
	void stop(){
		end=useconds();
	}
	
	long secs(){
		return (end-begin)/1_000_000;
	}
	
	long msecs(){
		long endTime=(end==0)?useconds():end;
		return (endTime-begin)/1000;
	}
	
	long usecs(){
		long endTime=(end==0)?useconds():end;
		return (endTime-begin);
	}
	
}

enum long ticksPerSecond=1_000_000;

// High precison timer, might be used for relative time measurements
long useconds(){
	version(Posix){
		timeval t;		
		gettimeofday(&t, null);		
		return t.tv_sec * 1000_000 + t.tv_usec ;
	}else version(Windows){
		__gshared double mul=-1;
		if(mul<0){
			long frequency;
			int ok=QueryPerformanceFrequency(&frequency);
			assert(ok);
			mul=1_000_000.0/frequency;
		}
		long ticks;
		int ok=QueryPerformanceCounter(&ticks);
		assert(ok);
		return cast(long)(ticks*mul);
	}else{
		static assert("OS not supported.");
	}
}


unittest{
	long ticks=useconds();
	assert(ticks>0);
	assert(useconds()>ticks);
}

