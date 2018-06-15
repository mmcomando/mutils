module mutils.bindings.libcoro;

enum CORO_VERSION = 3;

alias coro_func = extern (C) void function(void*);

extern (C) void coro_create(coro_context* ctx, coro_func coro, void* arg, void* sptr, size_t ssze);
extern (C) void coro_transfer(coro_context* prev, coro_context* next);
extern (C) void coro_destroy(coro_context* ctx);
extern (C) int coro_stack_alloc(coro_stack* stack, uint size);

struct coro_context {
	void*[128] data; // Platform/system dependant, this should be enought
}

struct coro_stack {
	void* sptr;
	size_t ssze;
	int valgrind_id;
}

// Does not work on Windows
/*version(Posix) unittest{
	
	__gshared static coro_context ctx, mainctx;
	__gshared static coro_stack stack;
	__gshared static int num;
	
	extern(C) static void coro_body(void *arg)
	{
		assert(num==0);
		num=1;
		coro_transfer(&ctx, &mainctx);
		assert(num==2);
		num=3;
		coro_transfer(&ctx, &mainctx);
		assert(0);
	}
		
	coro_create(&mainctx, null, null, null, 0);
	coro_stack_alloc(&stack, 0);
	coro_create(&ctx, &coro_body, null, stack.sptr, stack.ssze);
	
	assert(num==0);
	coro_transfer(&mainctx, &ctx);
	assert(num==1);
	num=2;
	coro_transfer(&mainctx, &ctx);
	assert(num==3);
}*/
