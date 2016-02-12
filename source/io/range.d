/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 *
 * Description:
 * This module provides _range interfaces for streams. This is useful for using
 * many of the _range operations in $(D std._range) and $(D std.algorithm).
 *
 * There is an important distinction between streams and ranges to be made.
 * Fundamentally, a stream is a unidirectional $(I stream) of bytes. That is,
 * there is no going backwards and there is no saving the current position (as
 * bidirectional and forward ranges can do). This provides a good mapping to
 * input ranges and output ranges. As streams only operate on raw bytes, ranges
 * provide an abstraction to operate on more complex data types.
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
        ubyte[] _buffer;

        // Length of valid data in the buffer
        size_t _valid;
    }

    /**
     * Initializes the range. A byte buffer with the given size is allocated to
     * hold the chunks.
     *
     * Params:
     *   source = A stream that can be read from.
     *   size = The size of each chunk to read at a time.
     */
    this(Stream source, size_t size = 4096)
    {
        this(source, new ubyte[](size));
    }

    /**
     * Initializes the range with the specified buffer. This is useful for
     * providing your own buffer that may be stack allocated.
     *
     * Params:
     *   source = A stream that can be read from.
     *   buffer = A byte array to hold each chunk as it is read.
     */
    this(Stream source, ubyte[] buffer)
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
     * Returns: The current chunk of the stream.
     *
     * Note that a full chunk is not guaranteed to be returned. In the event of
     * a partial read from the stream, this will be less than the maximum chunk
     * size. Code should be impartial to the size of the returned chunk.
     */
    const(ubyte)[] front() const pure
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
 * Convenience function for creating a $(D ByChunk) range over a stream.
 *
 * Example:
 * ---
 * import std.digest.digest : digest;
 * import std.digest.sha : SHA1;
 * import io.file;
 *
 * // Hash a file, 4KiB chunks at a time
 * ubyte[4096] buf;
 * auto sha1 = digest!SHA1(File("foo").byChunk(buf));
 * ---
 */
auto byChunk(Stream)(Stream stream, size_t size = 4096)
    if (isSource!Stream)
{
    return ByChunk!Stream(stream, size);
}

/// Ditto
auto byChunk(Stream)(Stream stream, ubyte[] buffer)
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

    auto f = tempFile.file;
    f.write(data);
    f.position = 0;

    assert(f.byChunk(4).equal(chunks));
}

/**
 * Wraps a stream in a range interface such that blocks of a fixed size are read
 * from the source. It is assumed that the stream is buffered so that
 * performance is not adversely affected.
 *
 * Since streams and ranges are fundamentally different, this is useful for
 * performing range operations on streams.
 *
 * Note: This is an input range and cannot be saved with $(D save()). Thus,
 * usage of this should not be mixed with the underlying stream without first
 * seeking to a specific location in the stream.
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

    /**
     * Initializes the range with a source stream.
     */
    this(Stream source)
    {
        _source = source;

        // Prime the cannons.
        popFront();
    }

    /**
     * Removes one block from the stream.
     */
    void popFront()
    {
        try
        {
            _source.readExactly((cast(ubyte*)&_current)[0 .. T.sizeof]);
        }
        catch (ReadException e)
        {
            _empty = true;
        }
    }

    /**
     * Returns: The current block in the stream.
     */
    @property ref const(T) front() const pure nothrow
    {
        return _current;
    }

    /**
     * The range is considered empty when less than $(D T.sizeof) bytes can be
     * read from the stream.
     *
     * Returns: True if there are no more blocks in the stream and false
     * otherwise.
     */
    @property bool empty() const pure nothrow
    {
        return _empty;
    }
}

/**
 * Helper function for constructing a block range.
 *
 * Example:
 * ---
 * import std.algorithm : equal;
 * import std.range : take;
 * ---
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

    // Write some data to the file
    auto f = tempFile.file;
    f.put(data);
    f.position = 0;

    // Read it back in, block-by-block
    assert(f.byBlock!Data.equal(data));
    assert(f.byBlock!Data.empty);
}

import std.range : back, isBidirectionalRange;

/**
 * Checks if the given region ends with the given separator.
 *
 * Returns: The number of elements that match.
 */
size_t endsWithSeparator(T, Separator)
    (const(T)[] region, const Separator separator)
    if (is(typeof(T.init == Separator.init) : bool))
{
    import std.range : back;
    return region.back == separator;
}

/// Ditto
size_t endsWithSeparator(T, Separator)
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

///
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
    const(T)[] front() const pure nothrow
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

unittest
{
    import std.range.primitives;
    import io.file : File;

    alias S = File;

    static assert(isInputRange!(Splitter!(char, char, S)));
    static assert(isInputRange!(Splitter!(char, string, S)));
    static assert(isInputRange!(Splitter!(int, int, S)));
    static assert(isInputRange!(Splitter!(int, immutable(int)[], S)));

    static assert(!isOutputRange!(Splitter!(char, char, S), char));
    static assert(!isForwardRange!(Splitter!(char, char, S)));
    static assert(!isBidirectionalRange!(Splitter!(char, char, S)));
    static assert(!isRandomAccessRange!(Splitter!(char, char, S)));
}

/**
 * Convenience function for returning a stream splitter.
 *
 * Params:
 *   T = Type of each element in the stream.
 *   stream = A sink stream that can be read from.
 *   separator = An element or range of elements to split on.
 *
 * Example:
 * ---
 * // Get a list of words from standard input.
 * import io;
 * import std.algorithm : map, filter;
 * import std.array : array;
 * auto words = stdin.splitter!char(' ')
 *                   .filter!(w => w != "")
 *                   .map!(w => w.idup)
 *                   .array;
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
    assert(tempFile.file.splitter!char('\n').equal(string[].init));
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

        auto f = tempFile.file;
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

    auto f = tempFile.file;
    f.writeExactly(data);
    f.position = 0;

    assert(f.splitter!char(' ').filter!(w => w != "").equal(result));
}
