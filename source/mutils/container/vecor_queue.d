module mutils.container.vecor_queue;

import core.bitop;
import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy, memset;
import std.stdio;

@nogc @safe nothrow pure size_t nextPow2()(size_t num) {
    return 1 << bsr(num) + 1;
}

struct VectorQueue(T) {
    T[] array;
    size_t begin;
    size_t end;

    ~this() {
        clear();
    }

    void clear() {
        removeAll();
    }

    void removeAll() {
        if (array !is null) {
            freeData(cast(void[]) array);
        }
        array = null;
        end = 0;
        begin = 0;
    }

    void reserve(size_t numElements) {
        if (numElements > array.length) {
            extend(numElements);
        }
    }

    void extend(size_t newNumOfElements) {
        auto oldArray = manualExtend(array, newNumOfElements);
        if (oldArray !is null) {
            freeData(oldArray);
        }
    }

    @nogc void freeData(void[] data) {
        // 0x0F probably invalid value for pointers and other types
        memset(data.ptr, 0x0F, data.length); // Makes bugs show up xD 
        free(data.ptr);
    }

    size_t length() {
        if (end >= begin) {
            return end - begin;
        }
        return array.length + end - begin;
    }

    void[] manualExtend(T[] oldArray, size_t newNumOfElements = 0) {
        if (newNumOfElements == 0)
            newNumOfElements = 2;
        size_t oldSize = oldArray.length * T.sizeof;
        size_t newSize = newNumOfElements * T.sizeof;
        T* memory = cast(T*) malloc(newSize);
        array = memory[0 .. newNumOfElements];

        size_t bbbbb = begin;
        size_t eeeee = end;
        size_t lll = length;
        size_t iterator = begin;
        size_t i = 0;
        if (oldArray) {
            do {
                if (iterator == end) {
                    break;
                }
                array[i] = oldArray[iterator];

                iterator++;

                if (iterator == oldArray.length) {
                    iterator = 0;
                }
                i++;
            }
            while (1);
        }
        end = i;
        begin = 0;

        return cast(void[]) oldArray;
    }

    void add()(auto ref T el) {
        if (array.length - length <= 1) {
            extend(nextPow2(array.length + 1));
        }
        array[end] = el;
        end++;
        if (end == array.length) {
            end = 0;
        }

    }

    T pop() {

        assert(begin != end);
        auto el = array[begin];
        begin++;
        if (begin == array.length) {
            begin = 0;
        }
        return el;
    }
}

unittest {
    VectorQueue!int queue;

    queue.add(1);
    queue.add(2);
    queue.add(3);

    assert(queue.length == 3);

    assert(queue.pop() == 1);
    assert(queue.pop() == 2);

    assert(queue.length == 1);
    assert(queue.array.length == 4);

    queue.add(5);
    queue.add(6);
    assert(queue.array.length == 4);
    assert(queue.pop() == 3);

    assert(queue.length == 2);

    assert(queue.pop() == 5);
    assert(queue.pop() == 6);
    assert(queue.length == 0);
    assert(queue.array.length == 4);

    foreach (int i; 0 .. 128) {
        queue.add(i);
    }

    foreach (int i; 0 .. 128) {
        assert(queue.pop() == i);
    }

}
