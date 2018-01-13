module mutils.timeline.executor;

import mutils.container.sorted_vector;
import mutils.container.vector;
import mutils.linalg.algorithm;
import mutils.timeline.utils;

alias ExecuteDelegate=void delegate();

struct ExecuteUnit{
	ExecuteDelegate del;
	float time;
}

struct Executor
{
	SortedVector!(ExecuteUnit, "a.time < b.time") toExecute;
	TimeIndexGetter indexGetter;



	void executeTo(float time){
		ExecuteUnit[] exe=indexGetter.passedFromLast(toExecute[], time);
		//writeln(exe);
		foreach(e; exe){
			e.del();
		}
	}

	void executeFromTo(float start, float end){
		indexGetter.set(toExecute[], start);
		executeTo(end);
	}
}


unittest{
	static struct Tmp{
		int value;

		void something(){
			value+=1;
		}
	}
	Tmp tmp;

	Executor exe;
	exe.toExecute~=ExecuteUnit(&tmp.something, 0);
	exe.toExecute~=ExecuteUnit(&tmp.something, 0);
	exe.toExecute~=ExecuteUnit(&tmp.something, 0);
	exe.toExecute~=ExecuteUnit(&tmp.something, 1);
	exe.toExecute~=ExecuteUnit(&tmp.something, 2);
	exe.toExecute~=ExecuteUnit(&tmp.something, 3);
	exe.toExecute~=ExecuteUnit(&tmp.something, 4);
	//Check executeTo
	exe.executeTo(0.1);
	exe.executeTo(0.1);
	assert(tmp.value==3);
	exe.executeTo(1.1);
	assert(tmp.value==4);
	exe.executeTo(2.1);
	assert(tmp.value==5);
	exe.executeTo(5);
	assert(tmp.value==7);
	//Check executeFromTo
	tmp.value=0;
	exe.executeFromTo(2, 10);
	assert(tmp.value==3);
	tmp.value=0;
	exe.executeFromTo(0, 10);
	assert(tmp.value==7);
}
