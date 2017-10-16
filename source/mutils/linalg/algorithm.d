module mutils.linalg.algorithm;

T mix(T)(T a, T b, float blend){
	return cast(T)(a+(b-a)*blend);
}

unittest{
	assert(mix(3, 5, 0.5)==4);
}