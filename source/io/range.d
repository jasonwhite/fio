/**
 * Copyright: Copyright Jason White, 2015
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.range;

import io.stream;


/**
 * Range that reads up to a fixed size chunk of data from a stream at a time.
 */
struct ByChunk(Stream)
    if (isSource!Stream)
{
    private
    {
        Stream _source;

        // Buffer to read in the data into.
        void[] _buffer;

        // Length of valid data in the buffer
        size_t _valid;
    }

    this(Stream source, size_t size = 4096)
    {
        this(source, new void[](size));
    }

    this(Stream source, void[] buffer)
    {
        _source = source;
        _buffer = buffer;
        popFront();
    }

    /**
     * Reads the next chunk from the stream.
     */
    void popFront()
    {
        _valid = _source.read(_buffer);
    }

    /**
     * Returns the current chunk of the stream.
     */
    const(void)[] front() const pure
    {
        return _buffer[0 .. _valid];
    }

    /**
     * Returns true if there are no more chunks to be read from the stream.
     */
    bool empty() const pure nothrow
    {
        return _valid == 0;
    }
}

/**
 * Convenience function for creating $(D ByChunk) range over a stream.
 */
auto byChunk(Stream)(Stream stream, size_t size = 4096)
    if (isSource!Stream)
{
    return ByChunk!Stream(stream, size);
}

/// Ditto
auto byChunk(Stream)(Stream stream, void[] buffer)
    if (isSource!Stream)
{
    return ByChunk!Stream(stream, buffer);
}

unittest
{
    import io.file.temp;
    import std.algorithm : equal;
    import std.array : join;

    immutable chunkSize = 4;
    immutable chunks = ["1234", "5678", "abcd", "efgh", "ij"];
    immutable data = chunks.join();

    auto f = tempFile();
    f.writeExactly(data);
    f.position = 0;

    assert(f.byChunk(4).equal(chunks));
}

/**
 * Wraps a stream in a range interface such that blocks of a fixed size are read
 * from the source. It is assumed that the stream is buffered such that
 * performance is not adversely affected.
 *
 * This range cannot be saved with $(D save()). As such, the usage of this
 * should not be mixed with the underlying stream without first seeking to a
 * specific location in the stream.
 */
struct ByBlock(T, Stream)
    if (isSource!Stream)
{
    private
    {
        Stream _source;

        // The current block in the stream.
        T _current;

        // Are we there yet?
        bool _empty = false;
    }

    this(Stream source)
    {
        _source = source;

        // Prime the cannons.
        popFront();
    }

    /**
     * Removes one block from the stream. The range is considered empty when
     * exactly 0 bytes can be read from the stream. Throws an exception if a
     * partial block is read.
     */
    void popFront()
    {
        immutable n = _source.read((&_current)[0 .. 1]);

        switch (n)
        {
            case 0:
                _empty = true;
                break;
            case T.sizeof:
                _empty = false;
                break;
            default:
                throw new ReadException("Read partial block from stream.");
        }
    }

    /**
     * Gets the current block in the stream.
     */
    @property ref const(T) front() const pure nothrow
    {
        return _current;
    }

    /**
     * Returns true if there are no more blocks in the stream.
     */
    @property bool empty() const pure nothrow
    {
        return _empty;
    }
}

/**
 * Helper function for constructing a block range.
 */
@property auto byBlock(T, Stream)(Stream stream)
    if (isSource!Stream)
{
    return ByBlock!(T, Stream)(stream);
}

unittest
{
    import io.file.temp;
    import std.algorithm : equal;

    static struct Data
    {
        int a, b, c;
    }

    immutable Data[] data = [
        {1, 2, 3},
        {4, 5, 6},
        {7, 8, 9},
    ];

    auto f = tempFile;
    f.put(data);
    f.position = 0;

    assert(f.byBlock!Data.equal(data));
    assert(f.byBlock!Data.empty);
}

// Checks if the region ends with a single element separator.
static private size_t endsWithSeparator(T, Separator)
    (const(T)[] region, const Separator separator)
    if (is(typeof(T.init == Separator.init) : bool))
{
    import std.range : back;
    return region.back == separator;
}

import std.range : back, isBidirectionalRange;

// Checks if the region ends with a range of elements.
static private size_t endsWithSeparator(T, Separator)
    (const(T)[] region, Separator sep)
    if (isBidirectionalRange!Separator &&
        is(typeof(T.init == sep.back.init) : bool))
{
    import std.range : back, empty, popBack;

    size_t common = 0;

    while (!region.empty && !sep.empty && region.back == sep.back)
    {
        region.popBack();
        sep.popBack();

        ++common;
    }

    return sep.empty ? common : 0;
}

/**
 * Checks if the given function can be used with $(D Splitter).
 */
enum isSplitFunction(alias fn, T, Separator) =
    is(typeof(fn(T[].init, Separator.init)));

unittest
{
    static assert(isSplitFunction!(endsWithSeparator, char, char));
    static assert(isSplitFunction!(endsWithSeparator, char, string));
}

/**
 * Splits a stream using a separator. The separator can be a single element or a
 * bidirectional range of elements.
 */
struct Splitter(T, Separator, Stream, alias splitFn = endsWithSeparator!(T, Separator))
    if (isSource!Stream && isSplitFunction!(splitFn, T, Separator))
{
    private
    {
        import std.array : Appender;

        alias Region = Appender!(T[]);

        // The current region
        Region _region;

        // Block iterator
        ByBlock!(T, Stream) _blocks;

        bool _empty = false;

        // Element or range that separates regions.
        const Separator _separator;
    }

    this(Stream source, const Separator separator)
    {
        _blocks = source.byBlock!(T, Stream);
        _separator = separator;

        // Prime the cannons
        popFront();
    }

    void popFront()
    {
        version (assert)
        {
            import core.exception : RangeError;
            if (empty) throw new RangeError();
        }

        _region.clear();

        if (_blocks.empty)
        {
            _empty = true;
            return;
        }

        while (!_blocks.empty)
        {
            _region.put(_blocks.front);

            if (auto len = splitFn(_region.data, _separator))
            {
                assert(_region.data.length >= len);
                _region.shrinkTo(_region.data.length - len);
                break;
            }

            _blocks.popFront();
        }

        _blocks.popFront();
    }

    /**
     * Gets the current region in the stream.
     */
    const(T)[] front()
    {
        version (assert)
        {
            import core.exception : RangeError;
            if (empty) throw new RangeError();
        }

        return _region.data;
    }

    /**
     * Returns true if there are no more regions in the splitter.
     */
    bool empty() const pure nothrow
    {
        return _empty;
    }
}

version (none) unittest
{
    import std.range;

    static assert(isInputRange!(Splitter!(char, char)));
    static assert(isInputRange!(Splitter!(char, string)));
    static assert(isInputRange!(Splitter!(int, int)));
    static assert(isInputRange!(Splitter!(int, int[])));

    static assert(!isOutputRange!(Splitter!(char, char)));
    static assert(!isForwardRange!(Splitter!(char, char)));
    static assert(!isBidirectionalRange!(Splitter!(char, char)));
    static assert(!isRandomAccessRange!(Splitter!(char, char)));
}

/**
 * Convenience function for returning a stream splitter.
 *
 * Example:
 * ---
 * // Reads and prints words.
 * import io;
 * import std.algorithm : filter;
 * foreach (word; stdin.splitter!char(' ').filter!(w => w != ""))
 *     println(word);
 * ---
 */
auto splitter(T = char, Separator, Stream)(Stream stream, Separator separator)
    if (isSource!Stream)
{
    return Splitter!(T, Separator, Stream)(stream, separator);
}

unittest
{
    // Test an empty split
    import io.file.temp;
    import std.algorithm : equal;
    assert(tempFile().splitter!char('\n').equal(string[].init));
}

version (unittest)
{
    void testSplitter(T, Separator)(const T[][] regions, Separator separator)
    {
        import io.file.temp;
        import std.array : join;
        import std.algorithm : equal;
        import std.traits : isArray;

        static if (isArray!Separator)
            auto joined = regions.join(separator);
        else
            auto joined = regions.join([separator]);

        auto f = tempFile();
        f.writeExactly(joined);
        f.position = 0;

        assert(f.splitter!T(separator).equal(regions));
        assert(f.position == joined.length * T.sizeof);

        // Add a trailing separator at the end of the file
        static if (isArray!Separator)
            f.writeExactly(separator);
        else
            f.writeExactly([separator]);
        f.position = 0;
        assert(f.splitter!T(separator).equal(regions));
    }
}

unittest
{
    // Test different types of separators.
    immutable lines = [
        "This is the first line",
        "",
        "That was a blank line.",
        "This is the penultimate line!",
        "This is the last line.",
    ];

    testSplitter(lines, '\n');
    testSplitter(lines, "\n");
    testSplitter(lines, "\r\n");
    testSplitter(lines, "\n\n");
    testSplitter(lines, "||||");
}

unittest
{
    // Test combining with filter
    import io.file.temp;
    import std.algorithm : filter, equal;

    immutable data = "The    quick brown  fox jumps over the lazy dog    ";
    immutable result = [
        "The", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog"
    ];

    auto f = tempFile();
    f.writeExactly(data);
    f.position = 0;

    assert(f.splitter!char(' ').filter!(w => w != "").equal(result));
}
