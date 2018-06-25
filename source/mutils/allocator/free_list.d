// Modified version of std/experimental/allocator/building_blocks/_free_list.d
// Orginal version did not support deallocateAll without parent allocator supporting it
// This version supports deallocateAll by using parents Allocator.deallocate to deallocate whole support buffer
module mutils.allocator.free_list;

import std.experimental.allocator.common;
import std.typecons : Flag, Yes, No;

/*
Returns `true` if `ptr` is aligned at `alignment`.
*/
@nogc nothrow pure
package bool alignedAt(T)(T* ptr, uint alignment)
{
    return cast(size_t) ptr % alignment == 0;
}

struct FreeList(ParentAllocator,
    size_t minSize, size_t maxSize = minSize,
    Flag!"adaptive" adaptive = No.adaptive)
{
    import std.conv : text;
    import std.exception : enforce;
    import std.traits : hasMember;
    import std.typecons : Ternary;
    import std.experimental.allocator.building_blocks.null_allocator : NullAllocator;

    static assert(minSize != unbounded, "Use minSize = 0 for no low bound.");
    static assert(maxSize >= (void*).sizeof,
        "Maximum size must accommodate a pointer.");

    private enum unchecked = minSize == 0 && maxSize == unbounded;

    private enum hasTolerance = !unchecked && (minSize != maxSize
        || maxSize == chooseAtRuntime);

    static if (minSize == chooseAtRuntime)
    {
        /**
        Returns the smallest allocation size eligible for allocation from the
        freelist. (If $(D minSize != chooseAtRuntime), this is simply an alias
        for `minSize`.)
        */
        @property size_t min() const
        {
            assert(_min != chooseAtRuntime);
            return _min;
        }
        /**
        If `FreeList` has been instantiated with $(D minSize ==
        chooseAtRuntime), then the `min` property is writable. Setting it
        must precede any allocation.

        Params:
        low = new value for `min`

        Precondition: $(D low <= max), or $(D maxSize == chooseAtRuntime) and
        `max` has not yet been initialized. Also, no allocation has been
        yet done with this allocator.

        Postcondition: $(D min == low)
        */
        @property void min(size_t low)
        {
            assert(low <= max || max == chooseAtRuntime);
            minimize;
            _min = low;
        }
    }
    else
    {
        alias min = minSize;
    }

    static if (maxSize == chooseAtRuntime)
    {
        /**
        Returns the largest allocation size eligible for allocation from the
        freelist. (If $(D maxSize != chooseAtRuntime), this is simply an alias
        for `maxSize`.) All allocation requests for sizes greater than or
        equal to `min` and less than or equal to `max` are rounded to $(D
        max) and forwarded to the parent allocator. When the block fitting the
        same constraint gets deallocated, it is put in the freelist with the
        allocated size assumed to be `max`.
        */
        @property size_t max() const { return _max; }

        /**
        If `FreeList` has been instantiated with $(D maxSize ==
        chooseAtRuntime), then the `max` property is writable. Setting it
        must precede any allocation.

        Params:
        high = new value for `max`

        Precondition: $(D high >= min), or $(D minSize == chooseAtRuntime) and
        `min` has not yet been initialized. Also $(D high >= (void*).sizeof). Also, no allocation has been yet done with this allocator.

        Postcondition: $(D max == high)
        */
        @property void max(size_t high)
        {
            assert((high >= min || min == chooseAtRuntime)
                && high >= (void*).sizeof);
            minimize;
            _max = high;
        }

        @system unittest
        {
            import std.experimental.allocator.common : chooseAtRuntime;
            import std.experimental.allocator.mallocator : Mallocator;

            FreeList!(Mallocator, chooseAtRuntime, chooseAtRuntime) a;
            a.min = 64;
            a.max = 128;
            assert(a.min == 64);
            assert(a.max == 128);
        }
    }
    else
    {
        alias max = maxSize;
    }

    private bool tooSmall(size_t n) const
    {
        static if (minSize == 0) return false;
        else return n < min;
    }

    private bool tooLarge(size_t n) const
    {
        static if (maxSize == unbounded) return false;
        else return n > max;
    }

    private bool freeListEligible(size_t n) const
    {
        static if (unchecked)
        {
            return true;
        }
        else
        {
            static if (minSize == 0)
            {
                if (!n) return false;
            }
            static if (minSize == maxSize && minSize != chooseAtRuntime)
                return n == maxSize;
            else
                return !tooSmall(n) && !tooLarge(n);
        }
    }

    static if (!unchecked)
    private void[] blockFor(Node* p)
    {
        assert(p);
        return (cast(void*) p)[0 .. max];
    }

    // statistics
    static if (adaptive == Yes.adaptive)
    {
        private enum double windowLength = 1000.0;
        private enum double tooFewMisses = 0.01;
        private double probMiss = 1.0; // start with a high miss probability
        private uint accumSamples, accumMisses;

        void updateStats()
        {
            assert(accumSamples >= accumMisses);
            /*
            Given that for the past windowLength samples we saw misses with
            estimated probability probMiss, and assuming the new sample wasMiss or
            not, what's the new estimated probMiss?
            */
            probMiss = (probMiss * windowLength + accumMisses)
                / (windowLength + accumSamples);
            assert(probMiss <= 1.0);
            accumSamples = 0;
            accumMisses = 0;
            // If probability to miss is under x%, yank one off the freelist
            static if (!unchecked)
            {
                if (probMiss < tooFewMisses && _root)
                {
                    auto b = blockFor(_root);
                    _root = _root.next;
                    parent.deallocate(b);
                }
            }
        }
    }

    private struct Node { Node* next; }
    static assert(ParentAllocator.alignment >= Node.alignof);

    // state
    /**
    The parent allocator. Depending on whether `ParentAllocator` holds state
    or not, this is a member variable or an alias for
    `ParentAllocator.instance`.
    */
    static if (stateSize!ParentAllocator) ParentAllocator parent;
    else alias parent = ParentAllocator.instance;
    private Node* root;
    static if (minSize == chooseAtRuntime) private size_t _min = chooseAtRuntime;
    static if (maxSize == chooseAtRuntime) private size_t _max = chooseAtRuntime;

    /**
    Alignment offered.
    */
    alias alignment = ParentAllocator.alignment;

    /**
    If $(D maxSize == unbounded), returns  `parent.goodAllocSize(bytes)`.
    Otherwise, returns `max` for sizes in the interval $(D [min, max]), and
    `parent.goodAllocSize(bytes)` otherwise.

    Precondition:
    If set at runtime, `min` and/or `max` must be initialized
    appropriately.

    Postcondition:
    $(D result >= bytes)
    */
    size_t goodAllocSize(size_t bytes)
    {
        assert(minSize != chooseAtRuntime && maxSize != chooseAtRuntime);
        static if (maxSize != unbounded)
        {
            if (freeListEligible(bytes))
            {
                assert(parent.goodAllocSize(max) == max,
                    text("Wrongly configured freelist: maximum should be ",
                        parent.goodAllocSize(max), " instead of ", max));
                return max;
            }
        }
        return parent.goodAllocSize(bytes);
    }

    private void[] allocateEligible(size_t bytes)
    {
        assert(bytes);
        if (root)
        {
            // faster
            auto result = (cast(ubyte*) root)[0 .. bytes];
            root = root.next;
            return result;
        }
        // slower
        static if (hasTolerance)
        {
            immutable toAllocate = max;
        }
        else
        {
            alias toAllocate = bytes;
        }
        assert(toAllocate == max || max == unbounded);
        auto result = parent.allocate(toAllocate);
        static if (hasTolerance)
        {
            if (result) result = result.ptr[0 .. bytes];
        }
        static if (adaptive == Yes.adaptive)
        {
            ++accumMisses;
            updateStats;
        }
        return result;
    }

    /**
    Allocates memory either off of the free list or from the parent allocator.
    If `n` is within $(D [min, max]) or if the free list is unchecked
    ($(D minSize == 0 && maxSize == size_t.max)), then the free list is
    consulted first. If not empty (hit), the block at the front of the free
    list is removed from the list and returned. Otherwise (miss), a new block
    of `max` bytes is allocated, truncated to `n` bytes, and returned.

    Params:
    n = number of bytes to allocate

    Returns:
    The allocated block, or `null`.

    Precondition:
    If set at runtime, `min` and/or `max` must be initialized
    appropriately.

    Postcondition: $(D result.length == bytes || result is null)
    */
    void[] allocate(size_t n)
    {
        static if (adaptive == Yes.adaptive) ++accumSamples;
        assert(n < size_t.max / 2);
        // fast path
        if (freeListEligible(n))
        {
            return allocateEligible(n);
        }
        // slower
        static if (adaptive == Yes.adaptive)
        {
            updateStats;
        }
        return parent.allocate(n);
    }

    // Forwarding methods
    mixin(forwardToMember("parent",
        "expand", "owns", "reallocate"));

    /**
    If `block.length` is within $(D [min, max]) or if the free list is
    unchecked ($(D minSize == 0 && maxSize == size_t.max)), then inserts the
    block at the front of the free list. For all others, forwards to $(D
    parent.deallocate) if `Parent.deallocate` is defined.

    Params:
    block = Block to deallocate.

    Precondition:
    If set at runtime, `min` and/or `max` must be initialized
    appropriately. The block must have been allocated with this
    freelist, and no dynamic changing of `min` or `max` is allowed to
    occur between allocation and deallocation.
    */
    bool deallocate(void[] block)
    {
        if (freeListEligible(block.length))
        {
            if (min == 0)
            {
                // In this case a null pointer might have made it this far.
                if (block is null) return true;
            }
            auto t = root;
            root = cast(Node*) block.ptr;
            root.next = t;
            return true;
        }
        static if (hasMember!(ParentAllocator, "deallocate"))
            return parent.deallocate(block);
        else
            return false;
    }

    /**
    Defined only if `ParentAllocator` defines `deallocateAll`. If so,
    forwards to it and resets the freelist.
    */
    static if (hasMember!(ParentAllocator, "deallocateAll"))
    bool deallocateAll()
    {
        root = null;
        return parent.deallocateAll();
    }

    /**
    Nonstandard function that minimizes the memory usage of the freelist by
    freeing each element in turn. Defined only if `ParentAllocator` defines
    `deallocate`. $(D FreeList!(0, unbounded)) does not have this function.
    */
    static if (hasMember!(ParentAllocator, "deallocate") && !unchecked)
    void minimize()
    {
        while (root)
        {
            auto nuke = blockFor(root);
            root = root.next;
            parent.deallocate(nuke);
        }
    }

    /**
    If `ParentAllocator` defines `deallocate`, the list frees all nodes
    on destruction. $(D FreeList!(0, unbounded)) does not deallocate the memory
    on destruction.
    */
    static if (!is(ParentAllocator == NullAllocator) &&
        hasMember!(ParentAllocator, "deallocate") && !unchecked)
    ~this()
    {
        minimize();
    }
}


/**
Free list built on top of exactly one contiguous block of memory. The block is
assumed to have been allocated with `ParentAllocator`, and is released in
`ContiguousFreeList`'s destructor (unless `ParentAllocator` is $(D
NullAllocator)).

`ContiguousFreeList` has most advantages of `FreeList` but fewer
disadvantages. It has better cache locality because items are closer to one
another. It imposes less fragmentation on its parent allocator.

The disadvantages of `ContiguousFreeList` over `FreeList` are its pay
upfront model (as opposed to `FreeList`'s pay-as-you-go approach), and a
hard limit on the number of nodes in the list. Thus, a large number of long-
lived objects may occupy the entire block, making it unavailable for serving
allocations from the free list. However, an absolute cap on the free list size
may be beneficial.

The options $(D minSize == unbounded) and $(D maxSize == unbounded) are not
available for `ContiguousFreeList`.
*/
struct ContiguousFreeList(ParentAllocator,
     size_t minSize, size_t maxSize = minSize)
{
    import std.experimental.allocator.building_blocks.null_allocator
        : NullAllocator;
    import std.experimental.allocator.building_blocks.stats_collector
        : StatsCollector, Options;
    import std.traits : hasMember;
    import std.typecons : Ternary;

    alias Impl = FreeList!(NullAllocator, minSize, maxSize);
    enum unchecked = minSize == 0 && maxSize == unbounded;
    alias Node = Impl.Node;

    alias SParent = StatsCollector!(ParentAllocator, Options.bytesUsed);

    // state
    /**
    The parent allocator. Depending on whether `ParentAllocator` holds state
    or not, this is a member variable or an alias for
    `ParentAllocator.instance`.
    */
    SParent parent;
    FreeList!(NullAllocator, minSize, maxSize) fl;
    void[] support;
    size_t allocated;

    /// Alignment offered.
    enum uint alignment = (void*).alignof;

    private void initialize(ubyte[] buffer, size_t itemSize = fl.max)
    {
        assert(itemSize != unbounded && itemSize != chooseAtRuntime);
        assert(buffer.ptr.alignedAt(alignment));
        immutable available = buffer.length / itemSize;
        if (available == 0) return;
        support = buffer;
        fl.root = cast(Node*) buffer.ptr;
        auto past = cast(Node*) (buffer.ptr + available * itemSize);
        for (auto n = fl.root; ; )
        {
            auto next = cast(Node*) (cast(ubyte*) n + itemSize);
            if (next == past)
            {
                n.next = null;
                break;
            }
            assert(next < past);
            assert(n < next);
            n.next = next;
            n = next;
        }
    }

    /**
    Constructors setting up the memory structured as a free list.

    Params:
    buffer = Buffer to structure as a free list. If `ParentAllocator` is not
    `NullAllocator`, the buffer is assumed to be allocated by `parent`
    and will be freed in the destructor.
    parent = Parent allocator. For construction from stateless allocators, use
    their `instance` static member.
    bytes = Bytes (not items) to be allocated for the free list. Memory will be
    allocated during construction and deallocated in the destructor.
    max = Maximum size eligible for freelisting. Construction with this
    parameter is defined only if $(D maxSize == chooseAtRuntime) or $(D maxSize
    == unbounded).
    min = Minimum size eligible for freelisting. Construction with this
    parameter is defined only if $(D minSize == chooseAtRuntime). If this
    condition is met and no `min` parameter is present, `min` is
    initialized with `max`.
    */
    static if (!stateSize!ParentAllocator)
    this(ubyte[] buffer)
    {
        initialize(buffer);
    }

    /// ditto
    static if (stateSize!ParentAllocator)
    this(ParentAllocator parent, ubyte[] buffer)
    {
        initialize(buffer);
        this.parent = SParent(parent);
    }

    /// ditto
    static if (!stateSize!ParentAllocator)
    this(size_t bytes)
    {
        initialize(cast(ubyte[])(ParentAllocator.instance.allocate(bytes)));
    }

    /// ditto
    static if (stateSize!ParentAllocator)
    this(ParentAllocator parent, size_t bytes)
    {
        initialize(cast(ubyte[])(parent.allocate(bytes)));
        this.parent = SParent(parent);
    }

    /// ditto
    static if (!stateSize!ParentAllocator
        && (maxSize == chooseAtRuntime || maxSize == unbounded))
    this(size_t bytes, size_t max)
    {
        static if (maxSize == chooseAtRuntime) fl.max = max;
        static if (minSize == chooseAtRuntime) fl.min = max;
        initialize(cast(ubyte[])(parent.allocate(bytes)), max);
    }

    /// ditto
    static if (stateSize!ParentAllocator
        && (maxSize == chooseAtRuntime || maxSize == unbounded))
    this(ParentAllocator parent, size_t bytes, size_t max)
    {
        static if (maxSize == chooseAtRuntime) fl.max = max;
        static if (minSize == chooseAtRuntime) fl.min = max;
        initialize(cast(ubyte[])(parent.allocate(bytes)), max);
        this.parent = SParent(parent);
    }

    /// ditto
    static if (!stateSize!ParentAllocator
        && (maxSize == chooseAtRuntime || maxSize == unbounded)
        && minSize == chooseAtRuntime)
    this(size_t bytes, size_t min, size_t max)
    {
        static if (maxSize == chooseAtRuntime) fl.max = max;
        fl.min = min;
        initialize(cast(ubyte[])(parent.allocate(bytes)), max);
        static if (stateSize!ParentAllocator)
            this.parent = SParent(parent);
    }

    /// ditto
    static if (stateSize!ParentAllocator
        && (maxSize == chooseAtRuntime || maxSize == unbounded)
        && minSize == chooseAtRuntime)
    this(ParentAllocator parent, size_t bytes, size_t min, size_t max)
    {
        static if (maxSize == chooseAtRuntime) fl.max = max;
        fl.min = min;
        initialize(cast(ubyte[])(parent.allocate(bytes)), max);
        static if (stateSize!ParentAllocator)
            this.parent = SParent(parent);
    }

    /**
    If `n` is eligible for freelisting, returns `max`. Otherwise, returns
    `parent.goodAllocSize(n)`.

    Precondition:
    If set at runtime, `min` and/or `max` must be initialized
    appropriately.

    Postcondition:
    $(D result >= bytes)
    */
    size_t goodAllocSize(size_t n)
    {
        if (fl.freeListEligible(n)) return fl.max;
        return parent.goodAllocSize(n);
    }

    /**
    Allocate `n` bytes of memory. If `n` is eligible for freelist and the
    freelist is not empty, pops the memory off the free list. In all other
    cases, uses the parent allocator.
    */
    void[] allocate(size_t n)
    {
        auto result = fl.allocate(n);
        if (result)
        {
            // Only case we care about: eligible sizes allocated from us
            ++allocated;
            return result;
        }
        // All others, allocate from parent
        return parent.allocate(n);
    }

    /**
    Defined if `ParentAllocator` defines it. Checks whether the block
    belongs to this allocator.
    */
    static if (hasMember!(SParent, "owns") || unchecked)
    // Ternary owns(const void[] b) const ?
    Ternary owns(void[] b)
    {
        if ((() @trusted => support && b
                            && (&support[0] <= &b[0])
                            && (&b[0] < &support[0] + support.length)
            )())
            return Ternary.yes;
        static if (unchecked)
            return Ternary.no;
        else
            return parent.owns(b);
    }

    /**
    Deallocates `b`. If it's of eligible size, it's put on the free list.
    Otherwise, it's returned to `parent`.

    Precondition: `b` has been allocated with this allocator, or is $(D
    null).
    */
    bool deallocate(void[] b)
    {
        if (support.ptr <= b.ptr && b.ptr < support.ptr + support.length)
        {
            // we own this guy
            assert(fl.freeListEligible(b.length));
            assert(allocated);
            --allocated;
            // Put manually in the freelist
            auto t = fl.root;
            fl.root = cast(Node*) b.ptr;
            fl.root.next = t;
            return true;
        }
        return parent.deallocate(b);
    }

    /**
    Deallocates everything from the parent.
    */
    static if (hasMember!(ParentAllocator, "deallocateAll")
        && stateSize!ParentAllocator)
    bool deallocateAll()
    {
        bool result = fl.deallocateAll && parent.deallocateAll;
        allocated = 0;
        return result;
    }

    /**    
    Deallocates everything(support) using the parent.
    */
    static if (!stateSize!ParentAllocator)
    bool deallocateAll()
    {
        bool result = parent.deallocate(support);
        allocated = 0;
        return result;
    }
    /**
    Returns `Ternary.yes` if no memory is currently allocated with this
    allocator, `Ternary.no` otherwise. This method never returns
    `Ternary.unknown`.
    */
    Ternary empty()
    {
        return Ternary(allocated == 0 && parent.bytesUsed == 0);
    }
}