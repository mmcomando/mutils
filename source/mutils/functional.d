module mutils.functional;

//TODO use taggedPointer https://dlang.org/phobos/std_bitmanip.html
import std.traits;

struct FunctionOrDelegate(DelegateOrFunctionType){
	static assert(isSomeFunction!DelegateOrFunctionType);
	alias Ret=ReturnType!DelegateOrFunctionType;
	alias Par=Parameters!DelegateOrFunctionType;
	
	alias DelegateType=Ret delegate(Par);
	alias FunctionType=Ret function(Par);
	union{
		DelegateType del;
		FunctionType func;
	}
	bool isDelegate;
	
	this(DelegateType cal){
		opAssign(cal);
	}
	this(FunctionType cal){
		opAssign(cal);
	}
	Ret opCall(Args...)(Args parameters){
		static assert(is(Args==Par));
		assert(func !is null);
		static if(is(Ret==void)){
			if(isDelegate){
				del(parameters);
			}else{
				func(parameters);
			}
		}else{
			if(isDelegate){
				return del(parameters);
			}else{
				return func(parameters);
			}
		}
	}
	
	void opAssign(DelegateType cal){
		del=cal;
		isDelegate=true;
	}
	void opAssign(FunctionType cal){
		func=cal;
		isDelegate=false;
	}
	bool opEquals(typeof(this) a){
		if(isDelegate!=a.isDelegate){
			return false;
		}
		if(isDelegate){
			return del==a.del;
		}else{
			return func==a.func;
		}
	}
}

