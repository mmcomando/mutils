module mutils.timeline.utils;

import std.traits;

struct TimeIndexGetter {
	uint lastIndex = 0;
	float lastTime = float.min_exp;

	void reset() {
		this = this.init;
	}

	void set(T)(in T[] slice, float time) {
		if (time <= slice[0].time || lastTime > time) {
			lastIndex = 0;
		}
		lastTime = time;
		foreach (uint i; lastIndex + 1 .. cast(uint) slice.length) {
			if (time <= slice[i].time) {
				lastIndex = i - 1;
				return;
			}

		}
		lastIndex = cast(uint) slice.length - 1;
	}

	uint[2] index(T)(in T[] slice, float time) {
		static assert(hasMember!(T, "time"));
		assert(slice.length < lastIndex.max);
		assert(slice.length > 0);
		if (lastIndex >= slice.length || lastTime > time) {
			lastIndex = 0;
		}

		lastTime = time;

		uint[2] ti;
		if (time <= slice[0].time) {
			lastIndex = 0;
			return ti;
		}
		foreach (uint i; lastIndex + 1 .. cast(uint) slice.length) {
			if (time <= slice[i].time) {
				ti[0] = i - 1;
				ti[1] = i;
				lastIndex = i - 1;
				return ti;
			}

		}
		lastIndex = cast(uint) slice.length - 2;
		uint last = cast(uint)(slice.length - 1);
		ti[0] = last;
		ti[1] = last;
		return ti;
	}

	T[] passedFromLast(T)(T[] slice, float time) {
		static assert(hasMember!(T, "time"));
		assert(slice.length < lastIndex.max);
		assert(slice.length > 0);

		scope (exit)
			lastTime = time;

		if (lastIndex > slice.length || lastTime > time || time <= slice[0].time) {
			lastIndex = 0;
			return null;
		}

		foreach (uint i; lastIndex + 1 .. cast(uint) slice.length) {
			if (time <= slice[i].time) {
				bool after = slice[lastIndex].time < lastTime;
				T[] ret = slice[lastIndex + after .. i];
				lastIndex = i - 1;
				return ret;
			}

		}
		bool after = slice[lastIndex].time < lastTime;
		T[] ret = slice[lastIndex + after .. slice.length];
		lastIndex = cast(uint) slice.length - 1;
		return ret;
	}
}

// Helper to avoid GC
private T[n] s(T, size_t n)(auto ref T[n] array) pure nothrow @nogc @safe {
	return array;
}

unittest {
	import std.algorithm : equal;

	struct Data {
		float time;
	}

	TimeIndexGetter getter;
	Data[5] data = [Data(0), Data(1), Data(2), Data(3), Data(4)];
	//Check index
	assert(getter.index(data, 0) == [0, 0].s);
	assert(getter.index(data, 5) == [4, 4].s);
	assert(getter.index(data, 1) == [0, 1].s);
	assert(getter.index(data, 4) == [3, 4].s);
	assert(getter.index(data, -5) == [0, 0].s);
	//Check passedFromLast
	assert(getter.passedFromLast(data, 0) == null);
	assert(getter.passedFromLast(data, 0.5) == data[0 .. 1]);
	assert(getter.passedFromLast(data, 0.5) == null);
	assert(getter.passedFromLast(data, 1.1) == data[1 .. 2]);
	assert(getter.passedFromLast(data, 1.1) == null);
	assert(getter.passedFromLast(data, 4.1) == data[2 .. 5]);
	assert(getter.passedFromLast(data, 5) == null);
	assert(getter.passedFromLast(data, 10) == null);
	assert(getter.passedFromLast(data, -10) == null);
	assert(getter.passedFromLast(data, 10) == data);
	//Check index after passedFromLast
	assert(getter.index(data, 15) == [4, 4].s);
	//Check set
	getter.set(data, 1.5);
	assert(getter.index(data, 1.7) == [1, 2].s);
	assert(getter.lastIndex == 1);
	assert(getter.passedFromLast(data, 2.5) == data[2 .. 3]);
	//Reset
	getter.reset();
	assert(getter == TimeIndexGetter.init);

}
