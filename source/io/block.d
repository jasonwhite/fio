/**
 * Copyright: Copyright Jason White, 2015
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.block;

import io.traits, io.stream;


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

    //@disable this(this);

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
    f.write(data);
    f.position = 0;

    assert(equal(data, f.byBlock!Data));
    assert(f.byBlock!Data.empty);
}

/*
 * Checks if the given delimiter is a valid delimiter for an element of type T.
 */
template isValidDelimiter(Delimiter, T)
{
    import std.traits : isScalarType, isArray, Unqual;
    import std.range : ElementEncodingType;

    static if (isScalarType!Delimiter)
    {
        enum isValidDelimiter = true;
    }
    else static if (isArray!Delimiter)
    {
        static if (is(Unqual!(ElementEncodingType!Delimiter) == T))
            enum isValidDelimiter = true;
        else
            enum isValidDelimiter = false;
    }
    else
        enum isValidDelimiter = false;
}

unittest
{
    static assert( isValidDelimiter!(char, char));
    static assert( isValidDelimiter!(string, char));
    static assert( isValidDelimiter!(dstring, dchar));
    static assert(!isValidDelimiter!(dstring, wchar));
    static assert(!isValidDelimiter!(dstring, char));
    static assert(!isValidDelimiter!(wstring, char));
    static assert( isValidDelimiter!(dchar, char));
    static assert( isValidDelimiter!(int, char));
    static assert( isValidDelimiter!(short, int));
}

struct ByDelimiter(T, Delimiter)
    if (isValidDelimiter!(Delimiter, T))
{
    private
    {
        import std.array : Appender;
        import io.block : ByBlock, byBlock;

        // Holds the current line
        Appender!(T[]) _line;

        // Iterates over the stream in small blocks
        ByBlock!T _blocks;

        // Are we there yet?
        bool _empty = false;

        // Character or sequence of characters that terminates a line.
        immutable Delimiter _delimiter;
    }

    @disable this(this);

    this(Source source, Delimiter delimiter)
    {
        _blocks = source.byBlock!T;
        _delimiter = delimiter;

        // Prime the cannons
        popFront();
    }

    /*
     * Finds the length of the delimiter relative to the size of a single
     * element in the line.
     */
    private @property size_t delimiterLength() const pure nothrow
    {
        import std.traits : isScalarType, isArray;

        static if (isScalarType!Delimiter)
        {
            return 1;
        }
        else static if (isArray!Delimiter)
        {
            return _delimiter.length;
        }
        else
        {
            static assert("Unable to find length of line delimiter");
        }
    }

    /**
     * Reads the next line.
     */
    void popFront()
    {
        import std.algorithm : endsWith;

        version(assert)
        {
            import core.exception : RangeError;
            if (empty) throw new RangeError();
        }

        _line.clear();

        if (_blocks.empty)
        {
            _empty = true;
            return;
        }

        foreach (immutable ch; _blocks)
        {
            _line.put(ch);

            if (_line.data.endsWith(_delimiter))
            {
                // Truncate the line to not include the delimiter
                // FIXME: Handle arrays and ranges of delimiters
                _line.shrinkTo(_line.data.length - delimiterLength);
                break;
            }
        }

        // popFront is not called when the loop exits, so we call it here.
        _blocks.popFront();
    }

    /**
     * Gets the current line in the stream.
     */
    const(T)[] front()
    {
        version(assert)
        {
            import core.exception : RangeError;
            if (empty) throw new RangeError();
        }

        return _line.data;
    }

    /**
     * Returns true if there are no more lines to read from the stream.
     */
    bool empty()
    {
        return _empty;
    }
}

/**
 * Convenience function for returning a delimiter range.
 */
@property auto byDelimiter(T = char, Delimiter)
    (Source source, Delimiter delimiter)
{
    return ByDelimiter!(T, Delimiter)(source, delimiter);
}

/**
 * Convenience function for returning a delimiter range that iterates over
 * lines.
 */
@property auto byLine(T)(Source source)
{
    return ByDelimiter!(T, dchar)(source, '\n');
}

version (unittest)
{
    void testByDelimiter(const string[] lines, string delimiter)
    {
        import io.file.temp;
        import std.array : join;
        import std.algorithm : equal;

        immutable text = lines.join(delimiter);

        auto f = tempFile();
        f.writeExactly(text);
        f.position = 0;

        assert(f.byDelimiter(delimiter).equal(lines));
        assert(f.position == text.length);

        // Add a trailing terminator at the end of the file.
        assert(f.write(delimiter) == delimiter.length);
        f.position = 0;
        assert(f.byDelimiter(delimiter).equal(lines));
    }
}

unittest
{
    immutable lines = [
        "This is the first line",
        "",
        "That was a blank line.",
        "This is the penultimate line!",
        "This is the last line.",
    ];

    testByDelimiter(lines, "\n");
    testByDelimiter(lines, "\r\n");
}
