module mutils.container.hash_map_tow_way;
import mutils.container.hash_map;

struct HashMapTwoWay(KeyOnePar, KeyTwoPar) {
	alias KeyOne = KeyOnePar;
	alias KeyTwo = KeyTwoPar;

	HashMap!(KeyOne, KeyTwo) keyOneToKeyTwo;
	HashMap!(KeyTwo, KeyOne) keyTwoToKeyOne;

	enum getIndexEmptyValue = keyOneToKeyTwo.getIndexEmptyValue;

	invariant {
		assert(keyOneToKeyTwo.length == keyTwoToKeyOne.length);
	}

	~this() {
		clear();
	}

	void clear() {
		keyOneToKeyTwo.clear();
		keyTwoToKeyOne.clear();
	}

	void reset() {
		keyOneToKeyTwo.reset();
		keyTwoToKeyOne.reset();
	}

	size_t length() {
		return keyOneToKeyTwo.length;
	}

	auto ref KeyTwo get()(auto ref KeyOne k, auto ref KeyTwo defaultValue) {
		size_t index = keyOneToKeyTwo.getIndex(k);
		if (index == getIndexEmptyValue) {
			return defaultValue;
		} else {
			return keyOneToKeyTwo.elements[index].keyValue.value;
		}
	}

	auto ref KeyOne get()(auto ref KeyTwo k, auto ref KeyOne defaultValue) {
		size_t index = keyTwoToKeyOne.getIndex(k);
		if (index == getIndexEmptyValue) {
			return defaultValue;
		} else {
			return keyTwoToKeyOne.elements[index].keyValue.value;
		}
	}

	void add()(auto ref KeyOne one, auto ref KeyTwo two) {
		size_t indexOne = keyOneToKeyTwo.getIndex(one);
		size_t indexTwo = keyTwoToKeyOne.getIndex(two);
		if (indexOne != getIndexEmptyValue) {
			KeyTwo value = keyOneToKeyTwo.elements[indexOne].keyValue.value;
			if (value != two) {
				keyTwoToKeyOne.remove(value);
				keyOneToKeyTwo.elements[indexOne].keyValue.value = two;
			}
		} else {
			keyOneToKeyTwo.add(one, two);

		}

		if (indexTwo != getIndexEmptyValue) {
			KeyOne value = keyTwoToKeyOne.elements[indexTwo].keyValue.value;
			if (value != one) {
				keyOneToKeyTwo.remove(value);
				keyTwoToKeyOne.elements[indexTwo].keyValue.value = one;
			}
		} else {
			keyTwoToKeyOne.add(two, one);
		}

	}

	void remove()(auto ref KeyOne one, auto ref KeyTwo two) {
		size_t indexOne = keyOneToKeyTwo.getIndex(one);
		size_t indexTwo = keyTwoToKeyOne.getIndex(two);
		if (indexOne == getIndexEmptyValue || indexTwo == getIndexEmptyValue) {
			assert(indexOne == indexTwo);
			return;
		}
		assert(keyOneToKeyTwo.elements[indexOne].keyValue.value == two);
		assert(keyTwoToKeyOne.elements[indexTwo].keyValue.value == one);
		keyOneToKeyTwo.remove(one);
		keyTwoToKeyOne.remove(two);
	}

	void remove()(auto ref KeyOne key) {
		size_t index = keyOneToKeyTwo.getIndex(key);
		if (index == getIndexEmptyValue) {
			return;
		}
		KeyTwo value = keyOneToKeyTwo.elements[index].keyValue.value;
		keyTwoToKeyOne.remove(value);
		keyOneToKeyTwo.remove(key);
	}

	void remove()(auto ref KeyTwo key) {
		size_t index = keyTwoToKeyOne.getIndex(key);
		if (index == getIndexEmptyValue) {
			return;
		}
		KeyOne value = keyTwoToKeyOne.elements[index].keyValue.value;
		keyOneToKeyTwo.remove(value);
		keyTwoToKeyOne.remove(key);
	}

}

unittest {
	HashMapTwoWay!(char, int) map;

	map.add('a', 1);
	assert(map.length == 1);
	assert(map.get('a', 0) == 1);
	assert(map.get(1, '\0') == 'a');

	map.add('a', 2);
	assert(map.length == 1);
	assert(map.get('a', 0) == 2);
	assert(map.get(1, '\0') == '\0');
	assert(map.get(2, '\0') == 'a');

	map.add('b', 2);
	assert(map.length == 1);
	assert(map.get('a', 0) == 0);
	assert(map.get('b', 0) == 2);
	assert(map.get(1, '\0') == '\0');
	assert(map.get(2, '\0') == 'b');

	map.add('c', 3);
	assert(map.length == 2);

	map.remove('b');
	assert(map.length == 1);

	map.remove(3);
	assert(map.length == 0);
}
