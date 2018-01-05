//Package for test, maybe there will be full implementation
module mutils.linalg.vec;

import std.math: sqrt;
import std.traits;

struct Vec(T, int dim){
	static assert(dim>0);
	enum dimension=dim;

	alias vector this;

	union{
		T[dim] vector;

		static if(dim==2){
			struct{
				T x;
				T y;
			}
		}
		
		static if(dim==3){
			struct{
				T x;
				T y;
				T z;
			}
		}
		
		static if(dim==4){
			struct{
				T x;
				T y;
				T z;
				T w;
			}
		}
	}
	this(T[dim] val){
		vector=val;
	}

	this(X)(X val) if( !isArray!X && isAssignable!(T, X)) {
		vector[]=val;
	}

	this(X)(X[dim] values) if( !isArray!X && isAssignable!(T, X)) {
		foreach(i, val; values){
			vector[i]=values[i];
		}
	}

	this(Args... )(Args values)	if(Args.length==dim) {
		foreach(i, val; values){
			vector[i]=values[i];
		}
	}

	float length(){
		float len=0;
		foreach(el; vector){
			len+=el*el;
		}
		return sqrt(len);
	}

	float length_squared(){
		float len=0;
		foreach(el; vector){
			len+=el*el;
		}
		return len;
	}

	Vec!(T, dim) normalized(){
		return this/length;
	}

	void normalize()(){
		this/=length;
	}

	Vec!(T, dim) opUnary(string s)() if (s == "-"){
		Vec!(T, dim) tmp=this;
		tmp*=-1;
		return tmp;
	}

	void opAssign(T[dim] rhs){
		vector=rhs;
	}

	auto opBinaryRight(string op, X)(X lft) if( isAssignable!(T, X)) {
		return this.opBinary!(op)(lft);
	}

	Vec!(T, dim) opBinary(string op)(T[dim] rhs)
	{
		Vec!(T, dim) ret;
		mixin("ret.vector=this.vector[] "~op~" rhs[];");
		return ret;
	}



	Vec!(T, dim) opBinary(string op)(double rhs){
		Vec!(T, dim) ret=this;
		foreach(ref v;ret.vector){
			mixin("v=cast(T)(v "~op~" rhs);");
			
		}
		return ret;
	}

	void opOpAssign(string op)(T rhs) {
		foreach(ref v; vector) {
			mixin("v" ~ op ~ "= rhs;");
		}
	}

	void opOpAssign(string op, X)(X[dim] rhs) if( !isArray!X && isAssignable!(T, X)) {
		foreach(i, ref v; vector) {
			mixin("v" ~ op ~ "= rhs[i];");
		}
	}


	import std.format:FormatSpec,formatValue;
	/**
	 * Preety print
	 */
	void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt) {
		formatValue(sink, vector, fmt);
	}

	import mutils.serializer.common;
	void customSerialize(Load load, Serializer, ContainerOrSlice)(Serializer serializer, ref ContainerOrSlice con){
		serializer.serialize!(load)(vector, con);
	}


}

@nogc nothrow pure unittest{
	alias vec2i=Vec!(int, 2);
	int[2] arr=[1,2];
	vec2i v1=vec2i(1, 1);
	vec2i v2=vec2i(3);
	vec2i v3=arr;
	assert(v2==vec2i(3, 3));
	v1.opBinary!("+")(v2);
	assert((v1+v2)==vec2i(4, 4));
	assert((v1*v2)==vec2i(3, 3));
	assert((v1/v2)==vec2i(0, 0));
	assert((v2/v1)==vec2i(3, 3));
	assert(v1*3.0==vec2i(3, 3));
}

@nogc nothrow pure unittest{
	alias vec2i=Vec!(int, 2);
	alias vec2b=Vec!(byte, 2);
	byte b1=1;
	int[2] arr=[1,2];
	vec2i v1=vec2i(1, 1);
	assert(v1*-1==vec2i(-1, -1));
	assert(-v1==vec2i(-1, -1));
	assert(vec2i(vec2b(b1, b1))==vec2i(1, 1));
}

@nogc nothrow pure unittest{
	alias vec2=Vec!(float, 2);
	vec2 v1=vec2(2, 2);
	v1*=2;
	assert(v1==vec2(4, 4));
	v1/=2;
	assert(v1==vec2(2, 2));
	assert(2*v1==vec2(4, 4));
	vec2 vN=v1.normalized;
	assert(vN[0]>0.7 && vN[0]<0.8);
	assert(vN[1]>0.7 && vN[1]<0.8);
	assert(v1==vec2(2, 2));
	v1.normalize();
	assert(v1[0]>0.7 && v1[0]<0.8);
	assert(v1[1]>0.7 && v1[1]<0.8);

}

auto dot(V)(V vA, V vB) if(!isStaticArray!V) {
	return dot(vA.vector, vB.vector);
}

auto dot(T)(T arrA, T arrB) if(isStaticArray!T) {
	ForeachType!T val;
	
	foreach(i; 0..T.length) {
		val += arrA[i] * arrB[i];
	}
	
	return val;
}

@nogc nothrow pure unittest{
	alias vec2i=Vec!(int, 2);
	int[2] arr=[1,2];
	vec2i vec=vec2i(arr);
	assert(dot(arr, arr)==5);
	assert(dot(vec, vec)==5);
}