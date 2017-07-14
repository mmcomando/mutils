/**
 * Some random functions
 */
module mutils.math;


import std.algorithm : min,max;
import std.math;
import std.stdio : writeln,writefln;
import std.traits;

import mutils.shapes;

import gl3n.linalg;

struct Transform{
	vec2 pos=vec2(0,0);
	float rot=0;
	float scale=1;
	
	Transform opBinary(string op)(Transform r) const
	{
		static if (op != "*")static assert(0, "Operator "~op~" not implemented");
		alias c = cos;
		alias s = sin;
		auto rPos=rotateVector(r.pos,rot);
		return Transform(
			rPos+pos,
			rot+r.rot,
			r.scale*scale
			);
	}
	
	mat4 toMatrix(){
		alias c = cos;
		alias s = sin;
		
		return mat4(scale * c(rot), -scale * s(rot), 0, pos.x,
			scale * s(rot),  scale * c(rot), 0, pos.y,
			0, 0, 1, 0,
			0, 0, 0, 1);
	}
	unittest{
		Transform t1,t2;
		t1=Transform(vec2(0,10),0,1);
		t2=Transform(vec2(0,20),0,1);
		assert((t1*t2).pos.y==30);
		
	}
}

float vectorToAngle(vec2 p) {
	return atan2(p.y,p.x);
}

vec2 rotateVector(vec2 p, float r) {
	float c = cos(r);
	float s = sin(r);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}


vec2[] getPointsOnCircle(vec2 pos, float r,int segments=64) {
	vec2[] points;
	points.reserve(segments);
	float delta = PI * 2 / (segments - 1);
	foreach (i; 0 .. segments) {
		float x = r * cos(delta * i);
		float y = r * sin(delta * i);
		points ~= vec2(x, y) + pos;
	}
	return points;
}




struct Camera {
    vec2 wh=vec2(100,1000);
    vec2 pos=vec2(0,0);
    float zoom=100;
    float rot=0;

    vec2 getCameraGlobalSize() {
        float windowRatio = cast(float) wh.y / wh.x;
        vec2 size = vec2(1 / windowRatio, 1);
        size /= zoom;
        return size;
    }

    vec2 cameraToGlobal(vec2i sreenPos) {
        vec2 global = sreenPos;
        global -= wh * 0.5;
        global.y *= -1 ;
        global /= zoom;
        global += pos;
        return global;
    }

    vec2i globalToCamera(vec2 pos) {
        pos -= this.pos;
        pos *= zoom ;
        pos.y *= -1 * wh.y;
        pos += wh * 0.5;
        return vec2i(cast(int) pos.x, cast(int) pos.y);
    }
    
}
