//Package for test, maybe there will be full implementation
module mutils.linalg.vec;

import std.math: sqrt;

struct Vec(T, int dim){
	static assert(dim>0);
	enum dimension=dim;

	union{
		T[dim] vector;

		static if(dim==2){
			struct{
				T x;
				T y;
			}
			struct{
				T w;
				T h;
			}
		}

		static if(dim==3){
			struct{
				T x;
				T y;
				T z;
			}
			struct{
				T w;
				T h;
			}
		}
	}

	this(Args... )(Args values){
		static assert(Args.length==dim || Args.length==1);
		
		static if(Args.length==1){
			vector[]=values[0];
		}else{
			foreach(i, val; values){
				vector[i]=values[i];
			}
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

	void opAssign(T[dim] rhs){
		vector=rhs;
	}

	Vec!(T, dim) opBinary(string op)(Vec!(T, dim) rhs)
	{
		Vec!(T, dim) ret;
		mixin("ret.vector=this.vector[] "~op~" rhs.vector[];");
		return ret;
	}

	Vec!(T, dim) opBinary(string op)(T[dim] rhs)
	{
		Vec!(T, dim) ret;
		mixin("ret.vector=this.vector[] "~op~" rhs[];");
		return ret;
	}

	Vec!(T, dim) opBinary(string op)(float rhs)
	{
		Vec!(T, dim) ret=this;
		foreach(ref v;ret.vector){
			mixin("v=cast(T)(v "~op~" rhs);");
			
		}
		return ret;
	}

	Vec!(T, dim) opBinary(string op)(double rhs)
	{
		Vec!(T, dim) ret=this;
		foreach(ref v;ret.vector){
			mixin("v=cast(T)(v "~op~" rhs);");
			
		}
		return ret;
	}


	import std.format:FormatSpec,formatValue;
	/**
	 * Preety print
	 */
	void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt)
	{
		formatValue(sink, vector, fmt);
	}

	import mutils.serializer.common;
	void customSerialize(Load load, Serializer, ContainerOrSlice)(Serializer serializer, ref ContainerOrSlice con){
		serializer.serialize!(load)(vector, con);
	}


}

unittest{
	int[2] arr=[1,2];
	alias vec2i=Vec!(int, 2);
	vec2i v1=vec2i(1, 1);
	vec2i v2=vec2i(3);
	vec2i v3=arr;
	assert(v2==vec2i(3, 3));
	v1.opBinary!("+")(v2);
	assert((v1+v2)==vec2i(4, 4));
	assert((v1*v2)==vec2i(3, 3));
	assert((v1/v2)==vec2i(0, 0));
	assert((v2/v1)==vec2i(3, 3));
}