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
struct ByChunk
{
    private
    {
        Source _source;

        // Buffer to read in the data into.
        void[] _buffer;

        // Length of valid data in the buffer
        size_t _valid;
    }

    @disable this(this);

    this(Source source, size_t size = 4096)
    {
        this(source, new void[](size));
    }

    this(Source source, void[] buffer)
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
@property ByChunk byChunk(Source source, size_t size = 4096)
{
    return ByChunk(source, size);
}

/// Ditto
@property ByChunk byChunk(Source source, void[] buffer)
{
    return ByChunk(source, buffer);
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
struct ByBlock(T)
{
    private
    {
        Source _source;

        // The current block in the stream.
        T _current;

        // Are we there yet?
        bool _empty = false;
    }

    @disable this(this);

    this(Source source)
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
@property auto byBlock(T)(Source source)
{
    return ByBlock!T(source);
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

struct Splitter(T, Separator, alias splitFn = endsWithSeparator!(T, Separator))
    if (isSplitFunction!(splitFn, T, Separator))
{
    private
    {
        import std.array : Appender;

        alias Region = Appender!(T[]);

        // The current region
        Region _region;

        // Block iterator
        ByBlock!T _blocks;

        bool _empty = false;

        // Element or range that separates regions.
        immutable Separator _separator;
    }

    @disable this(this);

    this(Source source, Separator separator)
    {
        _blocks = source.byBlock!T;
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

/**
 * Convenience function for returning a stream splitter.
 */
auto splitter(T = char, Separator)(Source source, Separator separator)
{
    return Splitter!(T, Separator)(source, separator);
}

unittest
{
    import io.file.temp;
    import std.array : join;
    import std.algorithm : equal;

    immutable lines = [
        "This is the first line",
        "",
        "That was a blank line.",
        "This is the penultimate line!",
        "This is the last line.",
    ];

    immutable text = lines.join("\n");

    auto f = tempFile();
    f.writeExactly(text);

    f.position = 0;
    assert(f.splitter!char('\n').equal(lines));

    f.position = 0;
    assert(f.splitter!char("\n").equal(lines));
}

unittest
{
    import io.file.temp;
    import std.array : join;
    import std.algorithm : equal;

    immutable lines = [
        "This is the first line",
        "",
        "That was a blank line.",
        "This is the penultimate line!",
        "This is the last line.",
    ];

    immutable text = lines.join("\r\n");

    auto f = tempFile();
    f.writeExactly(text);
    f.position = 0;
    assert(f.splitter!char("\r\n").equal(lines));
}
