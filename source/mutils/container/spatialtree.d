module mutils.container.spatialtree;

import std.traits:ForeachType;
import std.stdio;
import mutils.container.vector:DataContainer=Vector;

import mutils.container.buckets_chain;

struct Vector(Type, int dimension){
	Type[dimension] vector;

	this()(Type x, Type y){
		vector[0]=x;
		vector[1]=y;
	}
	this()(Type x, Type y, Type z){
		vector[0]=x;
		vector[1]=y;
		vector[2]=z;
	}

	alias vector this;
}

alias vec2=Vector!(float,2);
alias vec3=Vector!(float,3);


enum doNotInline="pragma(inline,false);version(LDC)pragma(LDC_never_inline);";


struct SpatialTree(ubyte dimension, T, bool loose=false){
	alias vec=Vector!(float,dimension);
	alias Point=float[dimension];
	alias DimType=ForeachType!Point;//dimension type
	alias isLoose=loose;
	alias QuadContainer=BucketsListChain!(Node[2^^Point.length], 128, false);

	float size=100;
	QuadContainer quadContainer;
	enum maxLevel=100;
	
	static struct PointData{
		T userData;
		static if(loose){
			Point pos;
			DimType radius;
		}
	}
	
	static struct Node{
		static if(loose){
			DataContainer!PointData dataContainer;
			Node* child;
		}else{
			union{
				DataContainer!PointData dataContainer;// Used only at lowest level
				Node* child;
			}
		}
		
	}
	
	Node root;
	
	void initialize(){}
	
	void clear(){
		root.child=null;
		root.dataContainer.clear();
		quadContainer.clear();
	}
	
	/////////////////////////
	///// Add functions /////
	/////////////////////////
	static if(loose){
		void add(vec posGlobal, float diameter, T data){
			Point pos=0;
			foreach(i,el;posGlobal.vector){
				if(el>size/2 || el<-size/2){
					root.dataContainer.add(PointData(data, pos, size/2));
					return;
				}
				pos[i]=el;
			}
			DimType diam=cast(DimType)(diameter);
			byte level=-1;
			DimType sizeTmp=size/2;
			while(sizeTmp>diam/4 && level<maxLevel){
				level++;
				sizeTmp/=2;
			}
			
			addToQuad(pos, PointData(data, pos, diam/2), &root, size/2, cast(ubyte)(maxLevel-level));
		}
	}else{
		void add(vec posGlobal,T data){
			Point pos=0;
			foreach(i,el;posGlobal.vector){
				if(el>size/2 || el<-size/2){
					return;
				}
				pos[i]=el;
			}
			addToQuad(pos, PointData(data), &root, size/2, 0);
		}
	}
	
	
	void addToQuad(Point pos, PointData data, Node* quad, DimType halfSize, ubyte level){
		mixin(doNotInline);
		while(level<maxLevel){
			if(quad.child is null){
				allocateQuads(quad, level);
			}
			DimType quarterSize=halfSize/2;
			bool[Point.length] direction;
			foreach(i;0..Point.length){
				direction[i]=pos[i]>0;
			}
			Point tt=quarterSize*(direction[]*2-1);
			int[2] tt2=direction[]*2-1;

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
	
	
	
	
	int visitAll(scope int delegate(Point pos, Node* quad, DimType halfSize, int level) visitor){
		Point pos=0;
		return visitAll(visitor,pos,&root, size/2,0);		
	}
	int visitAll(scope int delegate(Point pos, Node* quad, DimType halfSize, int level) visitor, Point pos, Node* quad, DimType halfSize, int level){
		int visitAllImpl(Point pos, Node* quad, DimType halfSize, int level){
			int res=visitor(pos, quad, halfSize, level);
			if(quad.child !is null && level<maxLevel){
				DimType quarterSize=halfSize/2;
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
	
	
	void visitAllNodesIn(scope int delegate(Point pos, Node* quad, DimType halfSize, int level) visitor, vec pdownLeft, vec pupRight){
		Point downLeft;
		Point upRight;
		
		foreach(i;0..Point.length){
			downLeft[i]=cast(DimType)(pdownLeft.vector[i]);
			upRight [i]=cast(DimType)(pupRight.vector[i]);
		}
		
		int check(Point pos, Node* quad, DimType halfSize, int level)
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
	
	
	void visitAllDataIn(scope void delegate(ref T data) visitor, vec pdownLeft, vec pupRight){
		Point downLeft;
		Point upRight;		
		foreach(i;0..Point.length){
			downLeft[i]=cast(DimType)(pdownLeft.vector[i]);
			upRight [i]=cast(DimType)(pupRight.vector[i]);
		}
		
		void visitAllDataNoCheck(Node* node, int level){
			if(hasElements(level)){
				foreach(ref pData;node.dataContainer){
					static if(loose){
						if(circleNotInBox(downLeft, upRight, pData.pos,pData.radius )){
							continue;
						}
					}
					visitor(pData.userData);			
				}
			}
			
			if(hasChildren(node, level)){
				enum uint nodesNumber=2^^Point.length;
				foreach(i;0..nodesNumber){
					visitAllDataNoCheck(&node.child[i], level+1);
				}
			}			
		}
		
		void visitAllDataImpl(Point pos, Node* node, DimType halfSize, int level){
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
						if(circleNotInBox(downLeft, upRight, pData.pos,pData.radius )){
							continue;
						}
					}
					visitor(pData.userData);				
				}
			}
			
			if(hasChildren(node, level)){
				DimType quarterSize=halfSize/2;
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
	
	static bool circleNotInBox(Point left, Point right,Point pos, DimType radius)  {
		bool ok=false;
		foreach(i;0..Point.length){
			ok|=(cast(long)pos[i]>cast(long)radius+cast(long)right[i]) || (cast(long)left[i]>cast(long)pos[i]+cast(long)radius);
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
	import std.meta;
	int numFound;
	int numOk;
	void test0(ref int num){numFound++;numOk+=num==0;}
	void test1(ref int num){numFound++;numOk+=num==1;}
	void test2(ref int num){numFound++;numOk+=num==2;}
	void test3(ref int num){numFound++;numOk+=num==3;}
	void test4(ref int num){numFound++;numOk+=num==4;}
	void test5(ref int num){numFound++;numOk+=num==5;}
	void test6(ref int num){numFound++;numOk+=num==6;}
	void test7(ref int num){numFound++;numOk+=num==7;}

	//Test Loose QuadTree
	{
		numFound=numOk=0;
		alias TestTree=SpatialTree!(2,int,true);
		TestTree tree;
		tree.initialize();
		tree.add(vec2(-1,+1), 0.1, 0);
		tree.add(vec2(+1,+1), 0.1, 1);
		tree.add(vec2(+1,-1), 0.1, 2);
		tree.add(vec2(-1,-1), 0.1, 3);		

		tree.visitAllDataIn(&test0,vec2(-10,0.1),vec2(-0.1, 10));
		tree.visitAllDataIn(&test1,vec2(0.1,0.1),vec2(10, 10));
		tree.visitAllDataIn(&test2,vec2(0.1,-10),vec2(10, -0.1));
		tree.visitAllDataIn(&test3,vec2(-10,-10),vec2(-0.1, -0.1));
		assert(numFound==4);
		assert(numOk==4);
	}

	//Test QuadTree
	{
		numFound=numOk=0;
		alias TestTree=SpatialTree!(2,int,false);
		TestTree tree;
		tree.initialize();
		
		tree.add(vec2(-5,+5), 0);
		tree.add(vec2(+5,+5), 1);
		tree.add(vec2(+5,-5), 2);
		tree.add(vec2(-5,-5), 3);
		
		
		tree.visitAllDataIn(&test0,vec2(-10,0.1),vec2(-0.1, 10));
		tree.visitAllDataIn(&test1,vec2(0.1,0.1),vec2(10, 10));
		tree.visitAllDataIn(&test2,vec2(0.1,-10),vec2(10, -0.1));
		tree.visitAllDataIn(&test3,vec2(-10,-10),vec2(-0.1, -0.1));
		assert(numFound==4);
		assert(numOk==4);
	}

	//Test Loose OctTree
	{
		numFound=numOk=0;
		alias TestTree=SpatialTree!(3,int,true);
		TestTree tree;
		tree.initialize();
		
		tree.add(vec3(-5,+5,+5), 0.1, 0);
		tree.add(vec3(+5,+5,+5), 0.1, 1);
		tree.add(vec3(+5,-5,+5), 0.1, 2);
		tree.add(vec3(-5,-5,+5), 0.1, 3);
		tree.add(vec3(-5,+5,-5), 0.1, 4);
		tree.add(vec3(+5,+5,-5), 0.1, 5);
		tree.add(vec3(+5,-5,-5), 0.1, 6);
		tree.add(vec3(-5,-5,-5), 0.1, 7);
		
		
		tree.visitAllDataIn(&test0,vec3(-10,0.1,0.1),vec3(-0.1, 10,10));
		tree.visitAllDataIn(&test1,vec3(0.1,0.1,0.1),vec3(10, 10,10));
		tree.visitAllDataIn(&test2,vec3(0.1,-10,0.1),vec3(10, -0.1,10));
		tree.visitAllDataIn(&test3,vec3(-10,-10,0.1),vec3(-0.1, -0.1,10));
		tree.visitAllDataIn(&test4,vec3(-10,0.1,-10),vec3(-0.1, 10,-0.1));
		tree.visitAllDataIn(&test5,vec3(0.1,0.1,-10),vec3(10, 10,-0.1));
		tree.visitAllDataIn(&test6,vec3(0.1,-10,-10),vec3(10, -0.1,-0.1));
		tree.visitAllDataIn(&test7,vec3(-10,-10,-10),vec3(-0.1, -0.1,-0.1));
		assert(numFound==8);
		assert(numOk==8);
	}


	//Test OctTree
	{
		numFound=numOk=0;
		alias TestTree=SpatialTree!(3,int,false);
		TestTree tree;
		tree.initialize();
		
		tree.add(vec3(-5,+5,+5), 0);
		tree.add(vec3(+5,+5,+5), 1);
		tree.add(vec3(+5,-5,+5), 2);
		tree.add(vec3(-5,-5,+5), 3);
		tree.add(vec3(-5,+5,-5), 4);
		tree.add(vec3(+5,+5,-5), 5);
		tree.add(vec3(+5,-5,-5), 6);
		tree.add(vec3(-5,-5,-5), 7);
		
		
		tree.visitAllDataIn(&test0,vec3(-10,0.1,0.1),vec3(-0.1, 10,10));
		tree.visitAllDataIn(&test1,vec3(0.1,0.1,0.1),vec3(10, 10,10));
		tree.visitAllDataIn(&test2,vec3(0.1,-10,0.1),vec3(10, -0.1,10));
		tree.visitAllDataIn(&test3,vec3(-10,-10,0.1),vec3(-0.1, -0.1,10));
		tree.visitAllDataIn(&test4,vec3(-10,0.1,-10),vec3(-0.1, 10,-0.1));
		tree.visitAllDataIn(&test5,vec3(0.1,0.1,-10),vec3(10, 10,-0.1));
		tree.visitAllDataIn(&test6,vec3(0.1,-10,-10),vec3(10, -0.1,-0.1));
		tree.visitAllDataIn(&test7,vec3(-10,-10,-10),vec3(-0.1, -0.1,-0.1));
		assert(numFound==8);
		assert(numOk==8);
	}
	
	
}

