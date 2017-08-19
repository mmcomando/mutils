module mutils.events;

import core.time;

alias vec2i=int[2];

Events gEvents;

enum MouseButton {
	left = 0,
	right = 1,
	middle = 2,	
}

enum Key {
	ctrl,
	alt,
	shift,
	F1,F2,F3,F4,F5,F6,F7,F8,F9,F10,F11,F12,
	up,down,left,right,
	esc
}
/**
 * Struct to store simple controller event states, like pressed, down, released.
 * Supports keyboard and mouse.
 * Additionaly this object calculates fps.
 * */
struct Events{

	bool[256] downKeys;
	bool[256] pressedKeys;
	bool[256] releasedKeys;
	bool[Key.max + 1] downKeysSpecial;
	bool[Key.max + 1] pressedKeysSpecial;
	bool[Key.max + 1] releasedKeysSpecial;

	bool[MouseButton.max + 1] mouseDownKeys;
	bool[MouseButton.max + 1] mousePressedKeys;
	bool[MouseButton.max + 1] mouseReleasedKeys;
	vec2i _mousePos = [100,100];
	vec2i _mouseWheel;

	alias Clock=MonoTimeImpl!(ClockType.precise);
	float dtf;
	float fps = 0;
	float minTime = 0;
	float maxTime = 0;
	long oldTime, newTime;

	bool quit = false;

	void initialzie(){
		newTime = Clock.currTime.ticks();
	}
	
	void update() {
		import core.stdc.string : memset;
		_mouseWheel = [0, 0];
		memset(&pressedKeys, 0, 256);
		memset(&releasedKeys, 0, 256);
		memset(&mousePressedKeys, 0, MouseButton.max + 1);
		memset(&mouseReleasedKeys, 0, MouseButton.max + 1);
		memset(&pressedKeysSpecial, 0, Key.max + 1);
		memset(&releasedKeysSpecial, 0, Key.max + 1);
		fpsCounter();
	}

	void fpsCounter() {
		static int frames;
		static float fpsTimer=0;
		static float miTime=0, maTime=0;
		long dt;

		frames++;
		oldTime = newTime;
		newTime = Clock.currTime.ticks();
		dt = newTime - oldTime;
		dtf = cast(float) dt/ Clock.ticksPerSecond;
		fpsTimer += dtf;
		if (miTime > dtf)
			miTime = dtf;
		if (maTime < dtf)
			maTime = dtf;
		if (fpsTimer >= 1) {
			minTime = miTime;
			maxTime = maTime;
			maTime = miTime = dtf;
			fps = cast(float)frames / fpsTimer;
			fpsTimer -= 1;
			frames = 0;
		}
		
	}
	
	
	vec2i mousePos() {
		return _mousePos;
	}
	
	vec2i mouseWheel() {
		return _mouseWheel;
	}
	
	bool mouseButtonDown(MouseButton b) {
		if (mouseDownKeys[b]) {
			return true;
		}
		return false;
	}
	
	bool mouseButtonPressed(MouseButton b) {
		
		if (mousePressedKeys[b]) {
			return true;
		}
		return false;
	}
	
	bool mouseButtonReleased(MouseButton b) {
		if (mouseReleasedKeys[b]) {
			return true;
		}
		return false;
	}
	
	bool keyPressed(short k) {
		if (k < 256) {
			return pressedKeys[k];
		} else {
			return false;
		}
	}
	
	bool keyReleased(short k) {
		if (k < 256) {
			return releasedKeys[k];
		} else {
			return false;
		}
	}
	
	bool keyDown(short k) {
		if (k < 256) {
			return downKeys[k];
		} else {
			return false;
		}
	}
	
	bool keyPressed(Key k) {
		if (k < 256) {
			return pressedKeysSpecial[k];
		} else {
			return false;
		}
	}
	
	bool keyReleased(Key k) {
		if (k < 256) {
			return releasedKeysSpecial[k];
		} else {
			return false;
		}
	}
	
	bool keyDown(Key k) {
		if (k < 256) {
			return downKeysSpecial[k];
		} else {
			return false;
		}
	}
	///////////////////////////////////////
	//// Events check implementations /////
	///////////////////////////////////////


	//https://dlang.org/blog/2017/02/13/a-new-import-idiom/
	// you don't have to import library if you dont use function
	template from(string moduleName)
	{
		mixin("import from = " ~ moduleName ~ ";");
	}

	void fromSDLEvent()(ref from!"derelict.sdl2.sdl".SDL_Event event){
		import derelict.sdl2.sdl;

		void specialKeysImpl(uint sym, bool up) {
			Key key;
			switch (sym) {
				//CONTROL ARROWS
				case SDLK_UP:key=Key.up;break;
				case SDLK_DOWN:key= Key.down;break;
				case SDLK_LEFT:key=Key.left;break;
				case SDLK_RIGHT:key=Key.right;break;
					//CONTROL KEYS
				case SDLK_ESCAPE:key=Key.esc;break;
				case SDLK_LCTRL:key= Key.ctrl;break;
				case SDLK_LSHIFT:key=Key.shift;break;
				case SDLK_LALT:key=Key.alt;break;
					//F_XX
				case SDLK_F1:key=Key.F1;break;
				case SDLK_F2:key=Key.F2;break;
				case SDLK_F3:key=Key.F3;break;
				case SDLK_F4:key=Key.F4;break;
				case SDLK_F5:key=Key.F5;break;
				case SDLK_F6:key=Key.F6;break;
				case SDLK_F7:key=Key.F7;break;
				case SDLK_F8:key=Key.F8;break;
				case SDLK_F9:key=Key.F9;break;
				case SDLK_F10:key=Key.F10;break;
				case SDLK_F11:key=Key.F11;break;
				case SDLK_F12:key=Key.F12;break;
				default:
					return;
			}
			if (!up) {
				downKeysSpecial[key] = true;
				pressedKeysSpecial[key] = true;
			} else {
				downKeysSpecial[key] = false;
				releasedKeysSpecial[key] = true;
			}
		}

		
		switch (event.type) {
			case SDL_KEYDOWN:
				specialKeysImpl(event.key.keysym.sym, false);
				if (event.key.keysym.sym < 256) {
					downKeys[event.key.keysym.sym] = true;
					pressedKeys[event.key.keysym.sym] = true;
				}
				
				break;
			case SDL_KEYUP:
				specialKeysImpl(event.key.keysym.sym, true);
				if (event.key.keysym.sym < 256) {
					downKeys[event.key.keysym.sym] = false;
					releasedKeys[event.key.keysym.sym] = true;
				}
				break;
			case SDL_MOUSEBUTTONDOWN:
				switch (event.button.button) {
					case SDL_BUTTON_LEFT:
						mouseDownKeys[MouseButton.left] = true;
						mousePressedKeys[MouseButton.left] = true;
						break;
					case SDL_BUTTON_RIGHT:
						mouseDownKeys[MouseButton.right] = true;
						mousePressedKeys[MouseButton.right] = true;
						break;
					case SDL_BUTTON_MIDDLE:
						mouseDownKeys[MouseButton.middle] = true;
						mousePressedKeys[MouseButton.middle] = true;
						break;
					default:
						break;
				}
				break;
			case SDL_MOUSEBUTTONUP:
				switch (event.button.button) {
					case SDL_BUTTON_LEFT:
						mouseDownKeys[MouseButton.left] = false;
						mouseReleasedKeys[MouseButton.left] = true;
						break;
					case SDL_BUTTON_RIGHT:
						mouseDownKeys[MouseButton.right] = false;
						mouseReleasedKeys[MouseButton.right] = true;
						break;
					case SDL_BUTTON_MIDDLE:
						mouseDownKeys[MouseButton.middle] = false;
						mouseReleasedKeys[MouseButton.middle] = true;
						break;
					default:
						break;
				}
				break;
			case SDL_MOUSEWHEEL:
				_mouseWheel.x = event.wheel.x;
				_mouseWheel.y = event.wheel.y;
				
				break;
			case SDL_QUIT:
				gEvents.quit = true;
				break;
			default:
				break;
		}
		
	}





}

