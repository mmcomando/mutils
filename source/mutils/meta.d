module mutils.meta;

import std.meta;

template removeEven(Arr...){
	static if(Arr.length>2){
		alias removeEven=AliasSeq!(Arr[1], removeEven!(Arr[2..$]));
	}else static if(Arr.length==2){
		alias removeEven=AliasSeq!(Arr[1]);
	}else{
		alias removeEven=AliasSeq!();
	}
}

unittest{
	static assert(is(removeEven!(int, float, long)==AliasSeq!(float)));
	static assert(is(removeEven!(int, float, long, float)==AliasSeq!(float, float)));
}


template removeOdd(Arr...){
	static if(Arr.length>2){
		alias removeOdd=AliasSeq!(Arr[0], removeOdd!(Arr[2..$]));
	}else static if(Arr.length==2){
		alias removeOdd=AliasSeq!(Arr[0]);
	}else{
		alias removeOdd=Arr;
	}
}

unittest{
	static assert(is(removeOdd!(int, float)==AliasSeq!(int)));
	static assert(is(removeOdd!(int, float, long)==AliasSeq!(int, long)));
}

template getType(alias T){
	alias getType=typeof(T);
}

unittest{
	static assert(is(getType!(6)==int));
}