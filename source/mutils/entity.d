module mutils.entity;

import std.format;
import std.stdio;
import std.traits;
import std.meta;

import mutils.container.buckets_chain;

/**
 * EntityId No Reference
 * Struct representing EntityId but without compile time information of EntityManager
 * Used to bypass forward reference problems
**/
struct EntityIdNR{
	@disable this(this);
	uint id;
	uint type;
}

bool hasComponent(Entity, Components...)(){
	bool has=true;
	foreach(Component;Components){
		enum componentNum=staticIndexOf!(Component,Fields!Entity);
		has = has & (componentNum!=-1);
	}
	return has;
}

struct EntityManager(Entities...){
	alias FromEntities=Entities;
	template EntitiesWithComponents(Components...){
		template EntityHasComponents(EEE){
			alias EntityHasComponents=hasComponent!(EEE, Components);
		}
		alias EntitiesWithComponents= Filter!(EntityHasComponents, FromEntities);
	}

	//Enum elements are well defined, 0->Entities[0], 1->Entities[1],
	//Enum EntityEnumM {...} // form mixin
	mixin(createEnumCode());
	alias EntityEnum=EntityEnumM;//Alias for autocompletion
	uint lastId=1;

	static struct EntityId{
		@disable this(this);
		uint id;
		EntityEnum type;
		
		auto get(EntityType)(){
			foreach(i,Ent;Entities){
				static if(is(EntityType==Ent)){
					assert(type==i);
					return cast(Ent*)(cast(void*)&this+8);
				}
			}
			assert(0);
		}

		Return apply(alias fun,Return=void)() {
			final switch(type){
				foreach(i,Ent;Entities){
					case cast(EntityEnum)i:
					Ent* el=get!Ent;
					if(is(Return==void)){
						fun(el);
						break;
					}else{
						return fun(el);
					}
				}
			}
			assert(0);
		}
		
		Component* getComponent(Component)(){
			foreach(i,Entity;Entities){
				enum componentNum=staticIndexOf!(Component,Fields!Entity);
				static if(componentNum!=-1){
					if(type==i){
						Entity* el=get!Entity;
						return &el.tupleof[componentNum];
					}
				}
			}
			assert(0);
		}
		
		auto hasComponent(Components...)(){
			foreach(i,Entity;Entities){
				if(type==i){
					return mutils.entity.hasComponent!(Entity, Components);
				}
			}
			assert(0);
		}

	}

	static struct EntityData(Ent){
		EntityId entityId;
		Ent entity;
		static assert(entity.offsetof==8);
		
		alias entity this;
	}

	template getEntityContainer(T){
		alias getEntityContainer = BucketsChain!(EntityData!(T));	
	}

	alias EntityContainers=staticMap!(getEntityContainer,Entities);
	EntityContainers entityContainers;

	@disable this(this);

	void initialize(){
		foreach(ref con;entityContainers){
			con.initialize;
		}

		foreach(Entity;Entities){
			Entity ent;
			foreach (i, ref m; ent.tupleof) {
				enum name = Entity.tupleof[i].stringof;
				alias typeof(m) Type;
				static if(hasStaticMember!(Type, "staticInitialize")){
					Type.staticInitialize();
				}
			}
		}
	}

	void destroy(){
		
		foreach(Entity;Entities){
			Entity ent;
			foreach (i, ref m; ent.tupleof) {
				enum name = Entity.tupleof[i].stringof;
				alias typeof(m) Type;
				static if(hasStaticMember!(Type, "staticDestroy")){
					Type.staticDestroy();
				}
			}
		}
	}

	size_t length(){
		size_t len;
		foreach(ref con;entityContainers){
			len+=con.length;
		}
		return len;
	}

	void clear(){
		foreach(ref con;entityContainers){
			con.clear();
		}
	}

	ref auto getContainer(EntityType)(){
		foreach(i,ent;Entities){
			static if(is(EntityType==ent)){
				return entityContainers[i];
			}
		}
		assert(0);
	}

	void update(){
		foreach(i, ref con;entityContainers){
			foreach(ref con.ElementType el;con){
				el.update();
			}

		}
	}

	EntityType* add(EntityType)(){
		EntityData!(EntityType)* ent=getContainer!(EntityType).add();
		ent.entityId.id=lastId++;
		ent.entityId.type=getEnum!EntityType;
		ent.entity.initialize();
		return &ent.entity;
	}

	EntityType* add(EntityType)(EntityType el){
		auto ent=add!(EntityType);
		ent.tupleof=el.tupleof;
		return ent;
	}

	void remove(EntityType)(EntityType* entity){
		entity.destroy();
		getContainer!(EntityType).remove(cast(EntityData!(EntityType)*)(cast(void*)entity-8));		
	}

	void remove(EntityId* entityId){
		foreach(i,Entity;Entities){
			if(entityId.type==i){
				Entity* ent=entityId.get!Entity;
				ent.destroy();
				getContainer!(Entity).remove(cast(EntityData!(Entity)*)(entityId));	
				return;
			}
		}
		assert(0);
		
	}


	auto allWith(Component)(){
		static struct ForeachStruct(T){
			T* mn;
			int opApply(Dg)(scope Dg dg)
			{ 
				int result;
				foreach(Entity;Entities){
					enum componentNum=staticIndexOf!(Component,Fields!Entity);
					static if(componentNum!=-1){
						foreach(ref EntityData!(Entity) el;mn.getContainer!(Entity)()){
							result=dg(el.entityId);
							if (result)
								break;			
						}
					}
				}
				return result;
			}
		}
		ForeachStruct!(typeof(this)) tmp;
		tmp.mn=&this;
		return tmp;
	}

	static EntityId* entityToEntityId(EntityType)(EntityType* el){
		static assert(!isPointer!(EntityType), "Wrong type passed. Maybe pointer to pointer was passed?");
		static assert(staticIndexOf!(EntityType, FromEntities)!=-1);
		EntityId* id=cast(EntityId*)(cast(void*)el-8);
		assert(id.type<Entities.length);
		return id;
	}

	/////////////////////////
	/////// Enum code  //////
	/////////////////////////
	static EntityEnum getEnum(T)(){
		foreach(i,Type;Entities){
			static if(is(Type==T)){
				return cast(EntityEnum)i;
			}
		}
	}

	
	static string getEntityName(EntityEnum type){
		foreach(i,Entity;Entities){
			if(type==i)
				return Entity.stringof;
		}
		return "!unknown";
	}
	//Order is very important
	static string createEnumCode(){
		string code="enum EntityEnumM:uint{";
		foreach(i,Entity;Entities){
			code~=format("_%d=%d,",i,i);
		}
		code~="}";
		return code;
	}
}





unittest{
	static int entitiesNum=0;
	
	static struct EntityTurrent{
		int a;

		void update(){}

		void initialize(){
			entitiesNum++;
		}
		
		void destroy(){
			entitiesNum--;
		}
	}
	static struct EntityTurrent2{
		int a;

		void update(){}

		void initialize(){
			entitiesNum++;
		}
		
		void destroy(){
			entitiesNum--;
		}
	}
	static struct EntitySomething{
		int a;

		void update(){
			
		}

		void initialize(){
			entitiesNum++;
		}
		
		void destroy(){
			entitiesNum--;
		}
	}
	
	
	alias TetstEntityManager=EntityManager!(
		EntityTurrent,
		EntityTurrent2,
		EntitySomething
		);

	TetstEntityManager entitiesManager;
	entitiesManager.initialize;
	assert(entitiesManager.getContainer!(EntityTurrent).length==0);
	assert(entitiesManager.getContainer!(EntityTurrent2).length==0);

	EntityTurrent* ret1=entitiesManager.add!(EntityTurrent)(EntityTurrent());
	EntityTurrent2* ret2=entitiesManager.add!(EntityTurrent2)(EntityTurrent2());

	assert(entitiesManager.getContainer!(EntityTurrent).length==1);
	assert(entitiesManager.getContainer!(EntityTurrent2).length==1);
	assert(entitiesNum==2);

	entitiesManager.remove(ret1);
	entitiesManager.remove(ret2);

	assert(entitiesManager.getContainer!(EntityTurrent).length==0);
	assert(entitiesManager.getContainer!(EntityTurrent2).length==0);
	assert(entitiesNum==0);
}

