module mutils.entity;

import std.format;
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


Component* getComponent(Component, Entity)(ref Entity ent)
	if(!isPointer!Entity)
{
	enum componentNum=staticIndexOf!(Component, Fields!Entity);
	static assert(componentNum!=-1, "Entity don't have this component.");
	return &ent.tupleof[componentNum];	
}

Component* getComponent(Component, Entity)(Entity* ent){
	enum componentNum=staticIndexOf!(Component, Fields!Entity);
	static assert(componentNum!=-1, "Entity don't have this component.");
	return &ent.tupleof[componentNum];	
}

struct EntityManager(ENTS){
	alias Entities=ENTS.Entities;
	alias FromEntities=Entities;
	alias UniqueComponents=NoDuplicates!(staticMap!(Fields, Entities));
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
			static assert(staticIndexOf!(Component, UniqueComponents)!=-1, "No entity has such component");

			foreach(i,Entity;Entities){
				enum componentNum=staticIndexOf!(Component,Fields!Entity);
				static if(componentNum!=-1){
					if(type==i){
						Entity* el=get!Entity;
						return &el.tupleof[componentNum];
					}
				}
			}
			assert(0, "There is no entity represented by this EntityId enum.");
		}
		
		auto hasComponent(Components...)(){
			foreach(C; Components){
				static assert(staticIndexOf!(C, UniqueComponents)!=-1, "No entity has such component");
			}
			foreach(i,Entity; Entities){
				if(type==i){
					return mutils.entity.hasComponent!(Entity, Components);
				}
			}

			assert(0, "There is no entity represented by this EntityId enum.");
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

	// Check compile time Entites requirements
	void checkEntities(){
		foreach(Entity;Entities){
			alias Components=Fields!Entity;
			// No duplicate components
			static assert(Components.length==NoDuplicates!(Components).length, "Entities should have unique components.");
		}
	}

	@disable this(this);

	void initialize(){
		foreach(Comp;UniqueComponents){
			static if(hasStaticMember!(Comp, "staticInitialize")){
				Comp.staticInitialize();
			}
		}
	}

	void destroy(){
		foreach(Comp;UniqueComponents){
			static if(hasStaticMember!(Comp, "staticDestroy")){
				Comp.staticDestroy();
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
		entityIdToStableId.clear();
		stableIdToEntityId.clear();
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

	// Adds enitiy without calling initialize on it, the user has to do it himself
	EntityType* addNoInitialize(EntityType, Components...)(Components components){
		EntityData!(EntityType)* entD=getContainer!(EntityType).add();
		entD.entityId.id=lastId++;
		entD.entityId.type=getEnum!EntityType;
		
		foreach(ref comp;components){
			auto entCmp=getComponent!(typeof(comp))(entD.entity);
			*entCmp=comp;
		}

		return &entD.entity;
	}

	EntityType* add(EntityType, Components...)(Components components){
		EntityType* ent=addNoInitialize!(EntityType)(components);
		ent.initialize();
		return ent;
	}

	void remove(EntityType)(EntityType* entity){
		EntityId* entId=entityToEntityId(entity);
		entity.destroy();
		getContainer!(EntityType).remove(cast(EntityData!(EntityType)*)(cast(void*)entity-8));
		long stableId=entityIdToStableId.get(entId, -1);	
		if(stableId==-1){
			return;
		}
		entityIdToStableId.remove(entId);
		stableIdToEntityId.remove(stableId);

	}

	void remove(EntityId* entityId){
		foreach(i,Entity;Entities){
			if(entityId.type==i){
				Entity* ent=entityId.get!Entity;
				remove(ent);
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

	// Based on pointer of component checks its base type
	EntityId* getEntityFromComponent(Component)(ref Component c){
		alias EntsWithComp=EntitiesWithComponents!(Component);
		static assert(EntsWithComp.length!=0, "There are no entities with this component.");

		foreach(Entity; EntsWithComp){
			auto container=&getContainer!(Entity)();
			foreach(ref bucket; container.buckets[]){
				if(!bucket.isIn(cast(container.ElementType*)&c)){
					continue;
				}
				enum componentNum=staticIndexOf!(Component,Fields!Entity);
				Entity el;
				enum ptrDt=el.tupleof[componentNum].offsetof;
				Entity* ent=cast(Entity*)(cast(void*)&c-ptrDt);
				return entityToEntityId(ent);
			}		
		}
		assert(0);
	}

	long lastStableId=0;

	long getUniqueStableId(){
		lastStableId++;
		return lastStableId;
	}

	import mutils.container.hash_map2;
	HashMap!(long, EntityId*) stableIdToEntityId;
	HashMap!(EntityId*, long) entityIdToStableId;


	// When (id == 0 && makeDefault !is null ) new id is assigned and Entity is created by makeDefault function
	EntityId* getEntityByStableId(ref long id, EntityId* function() makeDefault=null){
		EntityId* ent=stableIdToEntityId.get(id, null);

		if(ent==null && makeDefault !is null){
			ent=makeDefault();
			if(id==0){
				id=getUniqueStableId();
			}
			stableIdToEntityId[id]=ent;
			entityIdToStableId[ent]=id;
		}
		return ent;
	}

	void setEntityStableId(ref long id, EntityId* ent){
		if(id==0){
			id=getUniqueStableId();
		}
		stableIdToEntityId.add(id, ent);
		entityIdToStableId.add(ent, id);
	}
	
	auto getRange(Entity)(size_t start, size_t end){
		auto container=&getContainer!Entity();
		assert(end<=container.length);
		return Range!(Entity)(container, start, end);
	}

	struct Range(Entity){
		getEntityContainer!Entity* container;
		size_t start;
		size_t end;

		size_t length(){
			return end-start;
		}
		
		int opApply(Dg)(scope Dg dg){ 
			int result;
			// Can be improved: skip whole containers
			foreach(int i, ref EntityData!(Entity) el;*container){
				if(i<start){
					continue;
				}
				if(i>=end){
					break;
				}
				result=dg(el.entity);
				if (result)
					break;			
			}
			return result;
		}

	}

	static EntityId* entityToEntityId(EntityType)(EntityType* el){
		static assert(!isPointer!(EntityType), "Wrong type passed. Maybe pointer to pointer was passed?");
		static assert(staticIndexOf!(EntityType, FromEntities)!=-1, "There is no entity like: "~EntityType.stringof);
		EntityId* id=cast(EntityId*)(cast(void*)el-8);
		assert(id.type<Entities.length);
		return id;
	}
	
	static string getEntityName(EntityEnum type){
		foreach(i,Entity;Entities){
			if(type==i)
				return Entity.stringof;
		}
		return "!unknown";
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
	
	// Order if enum is important, indexing of objects is made out of it
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

	static struct ENTS{
		alias Entities=AliasSeq!(EntityTurrent,			EntityTurrent2,			EntitySomething);
	}
	
	alias TetstEntityManager=EntityManager!( ENTS );

	TetstEntityManager entitiesManager;
	entitiesManager.initialize;
	assert(entitiesManager.getContainer!(EntityTurrent).length==0);
	assert(entitiesManager.getContainer!(EntityTurrent2).length==0);

	EntityTurrent* ret1=entitiesManager.add!(EntityTurrent)(3);
	EntityTurrent2* ret2=entitiesManager.add!(EntityTurrent2)();

	assert(*ret1.getComponent!int==3);
	assert(*ret2.getComponent!int==0);

	assert(entitiesManager.getContainer!(EntityTurrent).length==1);
	assert(entitiesManager.getContainer!(EntityTurrent2).length==1);
	assert(entitiesManager.getEntityFromComponent(ret1.a).type==entitiesManager.getEnum!EntityTurrent);
	assert(entitiesNum==2);

	entitiesManager.remove(ret1);
	entitiesManager.remove(ret2);

	assert(entitiesManager.getContainer!(EntityTurrent).length==0);
	assert(entitiesManager.getContainer!(EntityTurrent2).length==0);
	assert(entitiesNum==0);
}

