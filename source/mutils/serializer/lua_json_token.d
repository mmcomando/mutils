module mutils.serializer.lua_json_token;

import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.meta;
import std.stdio : writeln;
import std.traits;

import mutils.serializer.common;
import mutils.serializer.lexer_utils;
/**
 * Serializer to save data in json|lua tokens format
 * If serialized data have to be allocated it is not saved/loaded unless it has "malloc" UDA (@("malloc"))
 */
class JSON_Lua_SerializerToken(bool isJson){
	/**
	 * Function loads and saves data depending on compile time variable load
	 * If useMalloc is true pointers, arrays, classes will be saved and loaded using Mallocator
	 * T is the serialized variable
	 * ContainerOrSlice is string when load==Load.yes 
	 * ContainerOrSlice container supplied by user in which data is stored when load==Load.no(save) 
	 */
	void serialize(Load load,bool useMalloc=false, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		try{
			static if(load==Load.yes){
				//pragma(msg, typeof(con));
				auto sss=NoGcSlice!(ContainerOrSlice)(con);
				serializeImpl!(load,useMalloc)(var, sss);
				con=sss[0..$];
			}else{
				serializeImpl!(load,useMalloc)(var, con);
			}
		}catch(Exception e){}
	}
	
	//support for rvalues during load
	void serialize(Load load,bool useMalloc=false, T, ContainerOrSlice)(ref T var,ContainerOrSlice con){
		static assert(load==Load.yes);
		serialize!(load,useMalloc)(var,con);		
	}

	__gshared static typeof(this) instance=new typeof(this);

package:
	
	void serializeImpl(Load load,bool useMalloc=false, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(
			(load==Load.yes && is(ForeachType!(ContainerOrSlice)==TokenData)) ||
			(load==Load.no  && is(ForeachType!(ContainerOrSlice)==TokenData))
			);
		static assert(load!=Load.skip,"Skip not supported");
		commonSerialize!(load,useMalloc)(this,var,con);
	}
	
	//-----------------------------------------
	//--- Basic serializing methods
	//-----------------------------------------
	void serializeBasicVar(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(isBasicType!T);
		static if (is(T==char)) {
			ser.serializeChar!(load)(var, con);
		}else{
			static if (load == Load.yes) {
				check!("Wrong token type")(con[0].isType!T);
				var = con[0].get!T();
				con=con[1..$];
			} else {
				TokenData token;
				token=var;
				con ~= token;
			}
		}
	}
	
	void serializeStruct(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(is(T == struct));
		
		
		serializeCharToken!(load)('{' ,con);
		static if(load==Load.yes){
			loadClassOrStruct!(load)(var,con);	
		}else{
			saveClassOrStruct!(load)(var,con);
		}
		
		serializeCharToken!(load)('}' ,con);
		
	}
	
	
	void serializeClass(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(is(T==class));
		
		serializeCharToken!(load)('{' ,con);
		static if(load==Load.yes){
			var=Mallocator.instance.make!(T);
			loadClassOrStruct!(load)(var,con);		
		}else{
			if(var !is null){
				saveClassOrStruct!(load)(var,con);
			}
		}
		serializeCharToken!(load)('}' ,con);
		
	}
	
	
	void serializeStaticArray(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(isStaticArray!T);
		serializeCharToken!(load)('[',con);
		foreach (i, ref a; var) {
			serializeImpl!(load)(a,con);
			if(i!=var.length-1){
				serializeCharToken!(load)(',',con);
			}
		}
		serializeCharToken!(load)(']',con);
		
	}
	
	
	void serializeDynamicArray(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(isDynamicArray!T);
		alias ElementType=Unqual!(ForeachType!(T));
		static if(is(ElementType==char)){
			static if (load == Load.yes) {
				assert(con[0].type==StandardTokens.string_);
				var=con[0].str;
				con=con[1..$];
			} else {
				TokenData token;
				token=var;
				token.type=StandardTokens.string_;
				con ~= token;
			}
		}else{	
			static if(load==Load.yes){
				import mutils.container.vector_allocator;
				VectorAllocator!(ElementType, Mallocator) arrData;				
				serializeCustomVector!(load)(arrData, con);
				var=cast(T)arrData[];
			}else{			
				serializeCustomVector!(load)(var, con);				
			}
		}
	}
	
	
	
	
	void serializeCustomVector(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static if(is(Unqual!(ForeachType!(T))==char)){
			serializeCustomVectorString!(load)(var, con);
		}else{
			alias ElementType=Unqual!(ForeachType!(T));
			uint dataLength=cast(uint)(var.length);
			serializeCharToken!(load)('[',con);
			
			static if(load==Load.yes){
				static if(hasMember!(T,"initialize")){
					var.initialize();
				}
				
				while(!con[0].isChar(']')){
					ElementType element;
					serializeImpl!(load)(element,con);
					var~=element;
					if(con[0].isChar(',')){
						serializeCharToken!(load)(',',con);
					}else{
						break;
					}
				}
				
			}else{
				foreach(i,ref d;var){
					serializeImpl!(load)(d,con);
					if(i!=var.length-1){
						serializeCharToken!(load)(',',con);
					}
				}
				
			}
			serializeCharToken!(load)(']',con);			
		}
	}
	
	
	void serializePointer(Load load,bool useMalloc, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		commonSerializePointer!(load,useMalloc)(this,var,con);		
	}
	
	//-----------------------------------------
	//--- Helper methods for basic methods
	//-----------------------------------------
	
	
	void loadClassOrStruct(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(load==Load.yes && (is(T==class) || is(T==struct)) );
		
		while(true){
			string varNa;
			serializeName!(load)(varNa,con);
			//scope(exit)Mallocator.instance.dispose(cast(string)varNa);
			bool loaded=false;
			foreach (i, ref a; var.tupleof) {
				alias TP = AliasSeq!(__traits(getAttributes, var.tupleof[i]));
				enum bool doSerialize=!hasNoserializeUda!(TP);
				enum bool useMalloc=hasMallocUda!(TP);
				enum string varName =__traits(identifier, var.tupleof[i]);
				static if(doSerialize){
					if(varName==varNa){
						try{
							auto tmpCon=con;
							scope(failure)con=tmpCon;//revert slice
							serializeImpl!(load,useMalloc)(a,con);
							loaded=true;
							break;
						}catch(Exception e){}
					}
				}
				
			}
			if(!loaded){
				ignoreToMatchingComma!(load)(con);
			}
			
			if(con[0].isChar(',')){
				con=con[1..$];
			}else{
				break;
			}
			
			
			
		}
	}
	
	
	void saveClassOrStruct(Load load, T, ContainerOrSlice)(ref T var,ref ContainerOrSlice con){
		static assert(load==Load.no && (is(T==class) || is(T==struct)) );
		foreach (i, ref a; var.tupleof) {
			alias TP = AliasSeq!(__traits(getAttributes, var.tupleof[i]));
			enum bool doSerialize=!hasNoserializeUda!(TP);
			enum bool useMalloc=hasMallocUda!(TP);
			enum string varNameTmp =__traits(identifier, var.tupleof[i]);
			string varName=cast(string)varNameTmp;
			serializeName!(load)(varName,con);
			serializeImpl!(load,useMalloc)(a,con);
			
			if(i!=var.tupleof.length-1){
				serializeCharToken!(load)(',' ,con);
			}
		}
	}
	
	static if(isJson){
		
		void serializeName(Load load,  ContainerOrSlice)(ref string name,ref ContainerOrSlice con){
			
			static if (load == Load.yes) {
				assert(con[0].type==StandardTokens.string_);
				name=con[0].getUnescapedString;
				con=con[1..$];
			} else {
				TokenData token;
				token=name;
				token.type=StandardTokens.string_;
				con ~= token;
			}
			serializeCharToken!(load)(':' ,con);
		}
	}else{

		void serializeName(Load load,  ContainerOrSlice)(ref string name,ref ContainerOrSlice con){
			
			static if (load == Load.yes) {
				assert(con[0].type==StandardTokens.identifier);
				name=con[0].str;
				con=con[1..$];
			} else {
				TokenData token;
				token=name;
				token.type=StandardTokens.identifier;
				con ~= token;
			}
			serializeCharToken!(load)('=' ,con);
		}
	}
}
