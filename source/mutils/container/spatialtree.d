module mutils.container.spatialtree;

import std.traits : ForeachType,hasMember;

import mutils.container.buckets_chain;
import mutils.container.vector : DataContainer = Vector;

template QuadTree(T, bool loose=false, ubyte maxLevel=8){
	alias QuadTree=SpatialTree!(2, T, loose, maxLevel);
}

template OcTree(T, bool loose=false, ubyte maxLevel=8){
	alias OcTree=SpatialTree!(3, T, loose, maxLevel);
}

/***
 * Implementation of QuadTree and OcTree, with loose bounds and without
 * Loose octree requires from type T to have member pos and radius, it can be function or variable.
 * */
struct SpatialTree(ubyte dimension, T, bool loose=false, ubyte maxLevel=8){
	static assert(dimension==2 || dimension==3, "Only QuadTrees and OcTrees are supported (dimension value: 2 or 3).");
	static assert(!loose || hasMember!(T, "pos") || hasMember!(T, "radius"), "Loose SpatialTree has to have members: pos and radius.");
	
	alias Point=float[dimension];
	alias isLoose=loose;
	alias QuadContainer=BucketsListChain!(Node[2^^Point.length], 128, false);
	
	float size=100;
	QuadContainer quadContainer;
	
	/* Example T
	 struct SpatialTreeData{
	 float[2] pos;
	 float radius;
	 MyData1 data1;
	 MyData* data2;
	 }
	 */
	
	static struct Node{
		//static if(loose){
		DataContainer!T dataContainer;
		Node* child;
		/*}else{
		 union{
		 DataContainer!T dataContainer;// Used only at lowest level
		 Node* child;
		 }
		 }*/
		
	}
	
	Node root;
	
	void initialize(){}

	~this(){
		clear();
	}
	
	void clear(){
		root.child=null;
		root.dataContainer.clear();
		quadContainer.clear();
	}

	
	void remove(Point posRemove, T data){
		int levelFrom=0;
		
		bool removeFormQuad(Point pos, Node* node, float halfSize, int level){	
			
			if(hasElements(level) && level>=levelFrom){
				bool ok=node.dataContainer.tryRemoveElement(data);
				if(ok)return true;
				//	else writeln("MISS");
			}
			
			if(hasChildren(node, level)){
				float quarterSize=halfSize/2;
				
				bool[Point.length] direction;
				foreach(i;0..Point.length){
					direction[i]=posRemove[i]>pos[i];
				}
				Point xy=pos[]+quarterSize*(direction[]*2-1);
				uint index=directionToIndex(direction);
				
				bool ok=removeFormQuad(xy,&node.child[index],quarterSize,level+1);
				if(ok)return true;
				
				enum uint nodesNumber=2^^Point.length;
				foreach(ubyte i;0..nodesNumber){
					if(i==index)continue;
					direction=indexToDirection(i);
					xy=pos[]+quarterSize*(direction[]*2-1);
					ok=removeFormQuad(xy,&node.child[i],quarterSize,level+1);
					if(ok)return true;
				}
			}
			if(hasElements(level) && level<levelFrom){
				bool ok=node.dataContainer.tryRemoveElement(data);
				if(ok)return true;
				//else writeln("MISS");
			}
			return false;
		}
		import std.stdio;

		static if(loose){
			foreach(i,el;posRemove){
				if(el>size/2 || el<-size/2){
					bool ok=root.dataContainer.tryRemoveElement(data);
					if(ok){
						return;
					}
				}
			}
		}
		Point pos=0;
		bool ok=removeFormQuad(pos, &root, size/2, 0);
		assert(ok,"Unable to find element in Tree");
	}

	/////////////////////////
	///// Add functions /////
	/////////////////////////
	
	void add(Point pos, T data){
		static if(loose){
			foreach(i,el;pos){
				if(el>size/2 || el<-size/2){
					root.dataContainer.add(data);
					return;
				}
			}
		}
		static if(loose){
			float diam=data.radius*2;
			byte level=-1;
			float sizeTmp=size/2;
			while(sizeTmp>diam/2 && level<maxLevel){
				level++;
				sizeTmp/=2;
			}
			
			addToQuad(pos, data, &root, size/2, cast(ubyte)(maxLevel-level));
		}else{
			addToQuad(pos, data, &root, size/2, 0);
		}
	}
	
	
	void addToQuad(Point pos, T data, Node* quad, float halfSize, ubyte level){
		while(level<maxLevel){
			if(quad.child is null){
				allocateQuads(quad, level);
			}
			float quarterSize=halfSize/2;
			bool[Point.length] direction;
			foreach(i;0..Point.length){
				direction[i]=pos[i]>0;
			}
			pos=pos[]-quarterSize*(direction[]*2-1);
			
			quad=&quad.child[directionToIndex(direction)];
			halfSize=quarterSize;
			level++;
		}
		quad.dataContainer.add(data);	
	}
	
	/////////////////////////
	//// Visit functions ////
	/////////////////////////
	
	
	
	
	int visitAll(scope int delegate(Point pos, Node* quad, float halfSize, int level) visitor){
		Point pos=0;
		return visitAll(visitor,pos,&root, size/2,0);		
	}
	int visitAll(scope int delegate(Point pos, Node* quad, float halfSize, int level) visitor, Point pos, Node* quad, float halfSize, int level){
		int visitAllImpl(Point pos, Node* quad, float halfSize, int level){
			int res=visitor(pos, quad, halfSize, level);
			if(quad.child !is null && level<maxLevel){
				float quarterSize=halfSize/2;
				enum uint nodesNumber=2^^Point.length;
				foreach(i;0..nodesNumber){
					auto direction=indexToDirection(i);
					Point xy=pos[]+quarterSize*(direction[]*2-1);
					res=visitAllImpl(xy,&quad.child[i],quarterSize,level+1);
					if(res)return res;
				}
			}	
			return res;			
		}
		return visitAllImpl(pos, quad, halfSize, level);		
	}	
	
	
	void visitAllNodesIn(scope int delegate(Point pos, Node* quad, float halfSize, int level) visitor, Point downLeft, Point upRight){
		
		int check(Point pos, Node* quad, float halfSize, int level)
		{
			if(quad.dataContainer.length>0){
				foreach( obj;quad.dataContainer){
					Point myDownLeft=pos[]-halfSize*(1+loose);//loose size is twice of a normal tree
					Point myUpRight =pos[]+halfSize*(1+loose);
					if(notInBox(downLeft, upRight, myDownLeft, myUpRight)){
						return 0;
					}
				}
			}
			bool hasElements=quad.dataContainer.length>0;
			static if(!loose){
				hasElements = hasElements && level>=maxLevel;//only leafs have data				
			}
			if(hasElements){
				int res=visitor(pos, quad, halfSize, level);
				if(res)return res;
			}
			return 0;
		}
		Point pos=0;
		visitAll(&check,pos,&root, size/2,0);
		
	}
	
	
	void visitAllDataIn(scope void delegate(ref T data) visitor, Point downLeft, Point upRight){
		
		void visitAllDataNoCheck(Node* node, int level){
			if(hasElements(level)){
				foreach(ref pData;node.dataContainer){
					visitor(pData);			
				}
			}
			
			if(hasChildren(node, level)){
				enum uint nodesNumber=2^^Point.length;
				foreach(i;0..nodesNumber){
					visitAllDataNoCheck(&node.child[i], level+1);
				}
			}			
		}
		
		void visitAllDataImpl(Point pos, Node* node, float halfSize, int level){
			Point myDownLeft=pos[]-halfSize*(1+loose);//loose size is twice of a normal tree
			Point myUpRight =pos[]+halfSize*(1+loose);
			if(notInBox(downLeft, upRight, myDownLeft, myUpRight)){
				return;
			}
			if(inBox(downLeft, upRight, myDownLeft, myUpRight)){
				visitAllDataNoCheck(node,level);
				return;
			}
			if(hasElements(level)){
				foreach(ref pData;node.dataContainer){
					static if(loose){
						if( circleNotInBox(downLeft, upRight, pData.pos, pData.radius) ){
							continue;
						}
					}
					visitor(pData);				
				}
			}
			
			if(hasChildren(node, level)){
				float quarterSize=halfSize/2;
				enum uint nodesNumber=2^^Point.length;
				foreach(i;0..nodesNumber){
					auto direction=indexToDirection(i);
					Point xy=pos[]+quarterSize*(direction[]*2-1);
					visitAllDataImpl(xy,&node.child[i],quarterSize,level+1);
				}
			}	
		}
		Point pos=0;
		visitAllDataImpl(pos, &root, size/2, 0);		
	}
	
	static if(hasMember!(T,"pos"))
	void updatePositions(){	
		void updatePositionsImpl(Point pos, Node* node, float halfSize, int level){
			if(hasElements(level)){
				Point myDownLeft=pos[]-halfSize*(1+loose);//loose size is twice of a normal tree
				Point myUpRight =pos[]+halfSize*(1+loose);
				foreach_reverse(i,pData;node.dataContainer){
					static if(loose){
						float radius=pData.radius;
					}else{
						float radius=0;
					}
					if(!circleInBox(myDownLeft, myUpRight, pData.pos, radius ) || (level!=maxLevel && (radius*2)<halfSize)){
						node.dataContainer.remove(i);
						add(pData.pos,pData);
					}			
				}
			}
			
			if(hasChildren(node, level)){
				float quarterSize=halfSize/2;
				enum uint nodesNumber=2^^Point.length;
				foreach(i;0..nodesNumber){
					auto direction=indexToDirection(i);
					Point xy=pos[]+quarterSize*(direction[]*2-1);
					updatePositionsImpl(xy,&node.child[i],quarterSize,level+1);
				}
			}	
		}
		Point pos=0;
		updatePositionsImpl(pos, &root, size/2, 0);		
	}

	
	
	/////////////////////////
	//// Helper functions ///
	/////////////////////////
	
	void allocateQuads(Node* quad, int level){
		auto xx=quadContainer.add();
		quad.child=cast(Node*)xx.ptr;
	}
	
	static bool notInBox(Point left, Point right,Point myLeft, Point myRight) pure nothrow{
		bool b0=(myRight[0]<left[0]) | (myLeft[0]>right[0]);
		bool b1=(myRight[1]<left[1]) | (myLeft[1]>right[1]);
		static if(Point.length==2){
			return b0 | b1;
		}else static if(Point.length==3){
			bool b2=(myRight[2]<left[2]) | (myLeft[2]>right[2]);
			return b0 | b1 | b2;
		}
	}
	
	static bool inBox(Point left, Point right,Point myLeft, Point myRight) pure nothrow{
		bool b0=(myLeft[0]>left[0]) & (myRight[0]<right[0]);
		bool b1=(myLeft[1]>left[1]) & (myRight[1]<right[1]);
		static if(Point.length==2){
			return b0 & b1;
		}else static if(Point.length==3){
			bool b2=(myLeft[2]>left[2]) & (myRight[2]<right[2]);
			return b0 & b1 & b2;
		}
	}
	
	static bool hasChildren(Node* node, int level)  {
		static if(loose){
			return node.child !is null;
		}else{
			return node.child !is null && level<maxLevel;
		}
	}
	
	static bool hasElements(int level)  {
		static if(loose){
			return true;
		}else{
			return level==maxLevel;
		}
	}
	
	static bool circleInBox(Point left, Point right,Point pos, float radius)  {
		bool ok=true;
		foreach(i;0..Point.length){
			ok&=(pos[i]+radius<right[i]) & (pos[i]-radius>left[i]);
		}
		return ok;
	}
	
	
	
	static bool circleNotInBox(Point left, Point right,Point pos, float radius)  {
		bool ok=false;
		foreach(i;0..Point.length){
			ok|=(pos[i]>radius+right[i]) | (left[i]>pos[i]+radius);
		}
		return ok;
	}
	
	static uint directionToIndex(bool[Point.length] dir) pure nothrow{
		static if(Point.length==2){
			return dir[0]+2*dir[1];
		}else static if(Point.length==3){
			return dir[0]+2*dir[1]+4*dir[2];
		}
	}
	
	static bool[Point.length] indexToDirection(uint index) pure nothrow{
		static if(Point.length==2){
			return [index==1 || index==3, index>=2];
		}else static if(Point.length==3){
			bool i3=index==3;
			bool i7=index==7;
			return [index==1 || i3 || index==5 || i7, index==2 || i3 || index==6 || i7, index>=4];
		}
	}
	
}
unittest{
	import mutils.container.vector;
	mixin(checkVectorAllocations);

	import mutils.linalg.vec;
	alias vec2=Vec!(float, 2);
	alias vec3=Vec!(float, 3);

	int numFound;
	int numOk;
	void test0(T)(ref T num){numFound++;numOk+=num.data==0;}
	void test1(T)(ref T num){numFound++;numOk+=num.data==1;}
	void test2(T)(ref T num){numFound++;numOk+=num.data==2;}
	void test3(T)(ref T num){numFound++;numOk+=num.data==3;}
	void test4(T)(ref T num){numFound++;numOk+=num.data==4;}
	void test5(T)(ref T num){numFound++;numOk+=num.data==5;}
	void test6(T)(ref T num){numFound++;numOk+=num.data==6;}
	void test7(T)(ref T num){numFound++;numOk+=num.data==7;}
	//Test Loose QuadTree
	{
		numFound=numOk=0;
		struct QuadTreeData1{
			float[2] pos;
			float radius;
			int data;
		}
		alias TestTree=SpatialTree!(2,QuadTreeData1,true);
		TestTree tree;
		tree.initialize();
		tree.add(vec2(-1,+1), QuadTreeData1(vec2(-1,+1),0.1,0));
		tree.add(vec2(+1,+1), QuadTreeData1(vec2(+1,+1),0.1,1));
		tree.add(vec2(+1,-1), QuadTreeData1(vec2(+1,-1),0.1,2));
		tree.add(vec2(-1,-1), QuadTreeData1(vec2(-1,-1),0.1,3));		
		
		tree.visitAllDataIn(&test0!QuadTreeData1,vec2(-10,0.1),vec2(-0.1, 10));
		tree.visitAllDataIn(&test1!QuadTreeData1,vec2(0.1,0.1),vec2(10, 10));
		tree.visitAllDataIn(&test2!QuadTreeData1,vec2(0.1,-10),vec2(10, -0.1));
		tree.visitAllDataIn(&test3!QuadTreeData1,vec2(-10,-10),vec2(-0.1, -0.1));
		assert(numFound==4);
		assert(numOk==4);
	}
	
	//Test QuadTree
	{
		numFound=numOk=0;
		struct QuadTreeData2{
			int data;
		}
		alias TestTree=SpatialTree!(2,QuadTreeData2,false);
		TestTree tree;
		tree.initialize();
		
		tree.add(vec2(-5,+5), QuadTreeData2(0));
		tree.add(vec2(+5,+5), QuadTreeData2(1));
		tree.add(vec2(+5,-5), QuadTreeData2(2));
		tree.add(vec2(-5,-5), QuadTreeData2(3));
		
		
		tree.visitAllDataIn(&test0!QuadTreeData2,vec2(-10,0.1),vec2(-0.1, 10));
		tree.visitAllDataIn(&test1!QuadTreeData2,vec2(0.1,0.1),vec2(10, 10));
		tree.visitAllDataIn(&test2!QuadTreeData2,vec2(0.1,-10),vec2(10, -0.1));
		tree.visitAllDataIn(&test3!QuadTreeData2,vec2(-10,-10),vec2(-0.1, -0.1));
		assert(numFound==4);
		assert(numOk==4);
	}
	
	//Test Loose OctTree
	{
		numFound=numOk=0;
		struct OctTreeData1{
			float[3] pos;
			float radius;
			int data;
		}
		alias TestTree=SpatialTree!(3,OctTreeData1,true);
		TestTree tree;
		tree.initialize();
		
		tree.add(vec3(-5,+5,+5), OctTreeData1(vec3(-5,+5,+5),0.1,0));
		tree.add(vec3(+5,+5,+5), OctTreeData1(vec3(+5,+5,+5),0.1,1));
		tree.add(vec3(+5,-5,+5), OctTreeData1(vec3(+5,-5,+5),0.1,2));
		tree.add(vec3(-5,-5,+5), OctTreeData1(vec3(-5,-5,+5),0.1,3));
		tree.add(vec3(-5,+5,-5), OctTreeData1(vec3(-5,+5,-5),0.1,4));
		tree.add(vec3(+5,+5,-5), OctTreeData1(vec3(+5,+5,-5),0.1,5));
		tree.add(vec3(+5,-5,-5), OctTreeData1(vec3(+5,-5,-5),0.1,6));
		tree.add(vec3(-5,-5,-5), OctTreeData1(vec3(-5,-5,-5),0.1,7));
		
		
		tree.visitAllDataIn(&test0!OctTreeData1,vec3(-10,0.1,0.1),vec3(-0.1, 10,10));
		tree.visitAllDataIn(&test1!OctTreeData1,vec3(0.1,0.1,0.1),vec3(10, 10,10));
		tree.visitAllDataIn(&test2!OctTreeData1,vec3(0.1,-10,0.1),vec3(10, -0.1,10));
		tree.visitAllDataIn(&test3!OctTreeData1,vec3(-10,-10,0.1),vec3(-0.1, -0.1,10));
		tree.visitAllDataIn(&test4!OctTreeData1,vec3(-10,0.1,-10),vec3(-0.1, 10,-0.1));
		tree.visitAllDataIn(&test5!OctTreeData1,vec3(0.1,0.1,-10),vec3(10, 10,-0.1));
		tree.visitAllDataIn(&test6!OctTreeData1,vec3(0.1,-10,-10),vec3(10, -0.1,-0.1));
		tree.visitAllDataIn(&test7!OctTreeData1,vec3(-10,-10,-10),vec3(-0.1, -0.1,-0.1));
		assert(numFound==8);
		assert(numOk==8);
	}
	
	
	//Test OctTree
	{
		numFound=numOk=0;
		struct OctTreeData2{
			int data;
		}
		alias TestTree=SpatialTree!(3,OctTreeData2,false);
		TestTree tree;
		tree.initialize();
		
		tree.add(vec3(-5,+5,+5), OctTreeData2(0));
		tree.add(vec3(+5,+5,+5), OctTreeData2(1));
		tree.add(vec3(+5,-5,+5), OctTreeData2(2));
		tree.add(vec3(-5,-5,+5), OctTreeData2(3));
		tree.add(vec3(-5,+5,-5), OctTreeData2(4));
		tree.add(vec3(+5,+5,-5), OctTreeData2(5));
		tree.add(vec3(+5,-5,-5), OctTreeData2(6));
		tree.add(vec3(-5,-5,-5), OctTreeData2(7));
		
		
		tree.visitAllDataIn(&test0!OctTreeData2,vec3(-10,0.1,0.1),vec3(-0.1, 10,10));
		tree.visitAllDataIn(&test1!OctTreeData2,vec3(0.1,0.1,0.1),vec3(10, 10,10));
		tree.visitAllDataIn(&test2!OctTreeData2,vec3(0.1,-10,0.1),vec3(10, -0.1,10));
		tree.visitAllDataIn(&test3!OctTreeData2,vec3(-10,-10,0.1),vec3(-0.1, -0.1,10));
		tree.visitAllDataIn(&test4!OctTreeData2,vec3(-10,0.1,-10),vec3(-0.1, 10,-0.1));
		tree.visitAllDataIn(&test5!OctTreeData2,vec3(0.1,0.1,-10),vec3(10, 10,-0.1));
		tree.visitAllDataIn(&test6!OctTreeData2,vec3(0.1,-10,-10),vec3(10, -0.1,-0.1));
		tree.visitAllDataIn(&test7!OctTreeData2,vec3(-10,-10,-10),vec3(-0.1, -0.1,-0.1));
		assert(numFound==8);
		assert(numOk==8);
	}
	
	
}

