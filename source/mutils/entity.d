module mutils.entity;

import std.algorithm : clamp, max, min;
import std.format : format;
import std.meta;
import std.traits;

import mutils.container.buckets_chain;
import mutils.container.hash_map;
import mutils.container.string_intern;
import mutils.time : useconds;
import mutils.container.hash_map_tow_way;

/**
 * EntityId No Reference
 * Struct representing EntityId but without compile time information of EntityManager
 * Used to bypass forward reference problems
 **/
struct EntityIdNR {
	@disable this(this);

	private StringIntern name;
	private StableId id;
	StringIntern triggerEventOnDestroy;
	bool doSerialization = true;
	int type = int.max;

	StableId stableIdNoAutoAdd() {
		return id;
	}
}

bool hasComponent(Entity, Components...)() {
	bool has = true;
	foreach (Component; Components) {
		enum componentNum = staticIndexOf!(Component, Fields!Entity);
		has = has & (componentNum != -1);
	}
	return has;
}

Component* getComponent(Component, Entity)(ref Entity ent) if (!isPointer!Entity) {
	enum componentNum = staticIndexOf!(Component, Fields!Entity);
	static assert(componentNum != -1, "Entity don't have this component.");
	return &ent.tupleof[componentNum];
}

Component* getComponent(Component, Entity)(Entity* ent) {
	enum componentNum = staticIndexOf!(Component, Fields!Entity);
	static assert(componentNum != -1, "Entity don't have this component.");
	return &ent.tupleof[componentNum];
}

struct StableId {
	private @("noserialize") ulong id;
}

struct EntityManager(ENTS) {
	alias Entities = ENTS.Entities;
	alias FromEntities = Entities;
	alias UniqueComponents = NoDuplicates!(staticMap!(Fields, Entities));
	template EntitiesWithComponents(Components...) {
		template EntityHasComponents(EEE) {
			alias EntityHasComponents = hasComponent!(EEE, Components);
		}

		alias EntitiesWithComponents = Filter!(EntityHasComponents, FromEntities);
	}

	//Enum elements are well defined, 0->Entities[0], 1->Entities[1],
	//Enum EntityEnumM {...} // form mixin
	mixin(createEnumCode());
	alias EntityEnum = EntityEnumM; //Alias for autocompletion

	enum memoryDtId = 32;

	private __gshared static HashMapTwoWay!(StringIntern, EntityId*) nameIdMap;
	private __gshared static HashMapTwoWay!(StableId, EntityId*) stableIdEntityIdMap;
	private __gshared static ulong lastStableId = 0;

	// Keep this struct in sync with  EntityIdNR
	static struct EntityId {
		@disable this(this);

		private StringIntern entityName;
		private StableId id;
		StringIntern triggerEventOnDestroy;
		bool doSerialization = true;
		EntityEnum type = EntityEnum.none;

		StableId stableId() {
			if (id.id != 0) {
				return id;
			}
			lastStableId++;
			id = StableId(lastStableId);
			stableIdEntityIdMap.add(id, &this);
			return id;
		}

		StableId stableIdNoAutoAdd() {
			return id;
		}

		StringIntern name() {
			return entityName;
		}

		void name(StringIntern newName) {
			if (newName == entityName) {
				return;
			}
			if (newName.length != 0) {
				EntityId* otherEnt = nameIdMap.get(newName, null);
				if (otherEnt !is null) {
					otherEnt.entityName = StringIntern();
					//nameIdMap.remove(newName);
				}
			}
			entityName = newName;
			nameIdMap.add(newName, &this);
		}

		auto get(EntityType)() {
			enum int entityEnumIndex = staticIndexOf!(EntityType, FromEntities);
			static assert(entityEnumIndex != -1, "There is no entity like: " ~ EntityType.stringof);

			assert(type == entityEnumIndex);
			return cast(EntityType*)(cast(void*)&this + memoryDtId);
		}

		Return apply(alias fun, Return = void)() {
			final switch (type) {
				foreach (i, Ent; Entities) {
			case cast(EntityEnum) i:
					Ent* el = get!Ent;
					if (is(Return == void)) {
						fun(el);
						break;
					} else {
						return fun(el);
					}
				}
			}
			assert(0);
		}

		Component* getComponent(Component)() {
			static assert(staticIndexOf!(Component, UniqueComponents) != -1,
					"No entity has such component");
			switch (type) {
				foreach (uint i, Entity; Entities) {
					enum componentNum = staticIndexOf!(Component, Fields!Entity);
					static if (componentNum != -1) {
			case cast(EntityEnumM) i:
						Entity* el = cast(Entity*)(cast(void*)&this + memoryDtId); // Inline get!Entity for debug performance
						return &el.tupleof[componentNum];
					}
				}
			default:
				break;
			}

			assert(0, "This entity does not have this component.");
		}

		auto hasComponent(Components...)() {
			foreach (C; Components) {
				static assert(staticIndexOf!(C, UniqueComponents) != -1,
						"No entity has such component");
			}
			switch (type) {
				foreach (uint i, Entity; Entities) {
			case cast(EntityEnumM) i:
					enum has = mutils.entity.hasComponent!(Entity, Components);
					return has;
				}
			default:
				break;
			}

			assert(0, "There is no entity represented by this EntityId enum."); //TODO log
			//return false;
		}

	}

	static struct EntityData(Ent) {
		EntityId entityId;
		Ent entity;
		static assert(entity.offsetof == memoryDtId);

		alias entity this;
	}

	template getEntityContainer(T) {
		alias getEntityContainer = BucketsChain!(EntityData!(T), 64, false);
	}

	alias EntityContainers = staticMap!(getEntityContainer, Entities);
	EntityContainers entityContainers;

	// Check compile time Entites requirements
	void checkEntities() {
		foreach (Entity; Entities) {
			alias Components = Fields!Entity;
			// No duplicate components
			static assert(Components.length == NoDuplicates!(Components)
					.length, "Entities should have unique components.");
		}
	}

	@disable this(this);

	void initialize() {
		foreach (Comp; UniqueComponents) {
			static if (hasStaticMember!(Comp, "staticInitialize")) {
				Comp.staticInitialize();
			}
		}
	}

	void destroy() {
		foreach (Comp; UniqueComponents) {
			static if (hasStaticMember!(Comp, "staticDestroy")) {
				Comp.staticDestroy();
			}
		}
	}

	size_t length() {
		size_t len;
		foreach (ref con; entityContainers) {
			len += con.length;
		}
		return len;
	}

	void clear() {
		foreach (ref con; entityContainers) {
			con.clear();
		}
		stableIdEntityIdMap.clear();
		nameIdMap.clear();
	}

	ref auto getContainer(EntityType)() {
		enum int entityEnumIndex = staticIndexOf!(EntityType, FromEntities);
		static assert(entityEnumIndex != -1, "There is no entity like: " ~ EntityType.stringof);
		return entityContainers[entityEnumIndex];
	}

	void update() {
		import mutils.benchmark;

		auto timeThis = TimeThis.time();
		foreach (i, ref con; entityContainers) {
			foreach (ref con.ElementType el; con) {
				el.update();
			}
		}

		foreach (i, ref con; entityContainers) {
			alias EntityType = typeof(con.ElementType.entity);
			alias TFields = Fields!EntityType;
			foreach (Type; TFields) {
				static if (hasMember!(Type, "updateTimely")) {
					updateTimely!(Type)(con);
				}
			}

		}

	}

	void updateTimely(Component, Container)(ref Container container) {
		static assert(hasMember!(Component, "updateTimely"));
		alias Entity = typeof(Container.ElementType.entity);

		static size_t startTime = 0;
		static size_t lastIndex = 0;
		static size_t lastUnitsPerFrame = 100;
		//static size_t sumUnitsOfWork=0;

		if (startTime == 0) {
			startTime = useconds();
		}

		size_t currentWork;
		auto range = getRange!(Entity)(lastIndex, container.length);
		foreach (ref Entity ent; range) {
			Component* comp = ent.getComponent!Component;
			currentWork += comp.updateTimely(ent);
			lastIndex += 1;
			if (currentWork > lastUnitsPerFrame) {
				break;
			}
		}
		//sumUnitsOfWork+=currentWork;
		if (lastIndex < container.length || startTime > useconds()) {
			return;
		}
		size_t endTime = useconds();
		size_t dt = endTime - startTime;

		startTime = endTime + Component.updateTimelyPeriod;

		float mul = cast(float) Component.updateTimelyPeriod / dt;
		mul = (mul - 1) * 0.5 + 1;

		lastUnitsPerFrame = cast(size_t)(lastUnitsPerFrame / mul);
		lastUnitsPerFrame = max(10, lastUnitsPerFrame);

		//sumUnitsOfWork=0;
		lastIndex = 0;

	}

	// Adds enitiy without calling initialize on it, the user has to do it himself
	EntityType* addNoInitialize(EntityType, Components...)(Components components) {
		EntityData!(EntityType)* entD = getContainer!(EntityType).add();
		entD.entityId.type = getEnum!EntityType;

		foreach (ref comp; components) {
			auto entCmp = getComponent!(typeof(comp))(entD.entity);
			*entCmp = comp;
		}

		return &entD.entity;
	}

	EntityType* add(EntityType, Components...)(Components components) {
		EntityType* ent = addNoInitialize!(EntityType)(components);
		ent.initialize();
		return ent;
	}

	void remove(EntityType)(EntityType* entity) {
		EntityId* entId = entityToEntityId(entity);
		entity.destroy();

		if (entId.id.id != 0) {
			stableIdEntityIdMap.remove(entId);
		} else {
			assert(stableIdEntityIdMap.get(entId, StableId()) == StableId());
		}

		if (entId.entityName != StringIntern()) {
			nameIdMap.remove(entId);
		} else {
			assert(nameIdMap.get(entId, StringIntern()) == StringIntern());

		}
		getContainer!(EntityType).remove(
				cast(EntityData!(EntityType)*)(cast(void*) entity - memoryDtId));

	}

	void remove(EntityId* entityId) {
		foreach (i, Entity; Entities) {
			if (entityId.type == i) {
				Entity* ent = entityId.get!Entity;
				remove(ent);
				return;
			}
		}
		assert(0);

	}

	// Based on pointer of component checks its base type
	EntityId* getEntityFromComponent(Component)(ref Component c) {
		alias EntsWithComp = EntitiesWithComponents!(Component);
		static assert(EntsWithComp.length != 0, "There are no entities with this component.");

		foreach (Entity; EntsWithComp) {
			auto container = &getContainer!(Entity)();
			foreach (ref bucket; container.buckets[]) {
				if (!bucket.isIn(cast(container.ElementType*)&c)) {
					continue;
				}
				enum componentNum = staticIndexOf!(Component, Fields!Entity);
				Entity el;
				enum ptrDt = el.tupleof[componentNum].offsetof;
				Entity* ent = cast(Entity*)(cast(void*)&c - ptrDt);
				return entityToEntityId(ent);
			}
		}
		assert(0);
	}

	// When (id == 0 && makeDefault !is null ) new id is assigned and Entity is created by makeDefault function
	EntityId* getEntityByStableId(ref StableId id, EntityId* function() makeDefault = null) {
		assert(id.id <= lastStableId);
		EntityId* ent = stableIdEntityIdMap.get(id, null);

		if (ent == null && makeDefault !is null) {
			ent = makeDefault();
			id = ent.stableId;
		}
		return ent;
	}

	EntityId* getEntityByName(StringIntern name) {
		EntityId* ent = nameIdMap.get(name, null);
		return ent;
	}

	void removeByStableId(StableId id) {
		if (id.id == 0) {
			return;
		}
		EntityId* ent = stableIdEntityIdMap.get(id, null);
		if (ent !is null) {
			remove(ent);
		}
	}

	auto getRange(Entity)(size_t start, size_t end) {
		auto container = &getContainer!Entity();
		assert(end <= container.length);
		return Range!(Entity)(container, start, end);
	}

	struct Range(Entity) {
		getEntityContainer!Entity* container;
		size_t start;
		size_t end;

		size_t length() {
			return end - start;
		}

		int opApply(Dg)(scope Dg dg) {
			int result;
			// Can be improved: skip whole containers
			int i;
			foreach (ref EntityData!(Entity) el; *container) {
				scope (exit)
					i++;
				if (i < start) {
					continue;
				}
				if (i >= end) {
					break;
				}
				result = dg(el.entity);
				if (result)
					break;
			}
			return result;
		}

	}

	static EntityId* entityToEntityId(EntityType)(EntityType* el) {
		static assert(!isPointer!(EntityType),
				"Wrong type passed. Maybe pointer to pointer was passed?");
		static assert(staticIndexOf!(EntityType, FromEntities) != -1,
				"There is no entity like: " ~ EntityType.stringof);
		EntityId* id = cast(EntityId*)(cast(void*) el - memoryDtId);
		assert(id.type < Entities.length);
		return id;
	}

	static string getEntityEnumName(EntityEnum type) {
		foreach (i, Entity; Entities) {
			if (type == i)
				return Entity.stringof;
		}
		return "!unknown";
	}
	/////////////////////////
	/////// Enum code  //////
	/////////////////////////
	static EntityEnum getEnum(EntityType)() {
		enum int entityEnumIndex = staticIndexOf!(EntityType, FromEntities);
		static assert(entityEnumIndex != -1, "There is no entity like: " ~ EntityType.stringof);
		return cast(EntityEnum) entityEnumIndex;

	}

	// Order if enum is important, indexing of objects is made out of it
	static string createEnumCode() {
		string code = "enum EntityEnumM:int{";
		foreach (i, Entity; Entities) {
			code ~= format("_%d=%d,", i, i);
		}
		code ~= format("none");
		code ~= "}";
		return code;
	}

}

unittest {
	static int entitiesNum = 0;

	static struct EntityTurrent {
		int a;

		void update() {
		}

		void initialize() {
			entitiesNum++;
		}

		void destroy() {
			entitiesNum--;
		}
	}

	static struct EntityTurrent2 {
		int a;

		void update() {
		}

		void initialize() {
			entitiesNum++;
		}

		void destroy() {
			entitiesNum--;
		}
	}

	static struct EntitySomething {
		int a;

		void update() {

		}

		void initialize() {
			entitiesNum++;
		}

		void destroy() {
			entitiesNum--;
		}
	}

	static struct ENTS {
		alias Entities = AliasSeq!(EntityTurrent, EntityTurrent2, EntitySomething);
	}

	alias TetstEntityManager = EntityManager!(ENTS);

	TetstEntityManager entitiesManager;
	entitiesManager.initialize;
	assert(entitiesManager.getContainer!(EntityTurrent).length == 0);
	assert(entitiesManager.getContainer!(EntityTurrent2).length == 0);

	EntityTurrent* ret1 = entitiesManager.add!(EntityTurrent)(3);
	EntityTurrent2* ret2 = entitiesManager.add!(EntityTurrent2)();

	assert(*ret1.getComponent!int == 3);
	assert(*ret2.getComponent!int == 0);

	assert(entitiesManager.getContainer!(EntityTurrent).length == 1);
	assert(entitiesManager.getContainer!(EntityTurrent2).length == 1);
	assert(entitiesManager.getEntityFromComponent(ret1.a)
			.type == entitiesManager.getEnum!EntityTurrent);
	assert(entitiesNum == 2);

	entitiesManager.remove(ret1);
	entitiesManager.remove(ret2);

	assert(entitiesManager.getContainer!(EntityTurrent).length == 0);
	assert(entitiesManager.getContainer!(EntityTurrent2).length == 0);
	assert(entitiesNum == 0);
}
