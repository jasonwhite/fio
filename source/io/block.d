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
    private Source _source;

    this(Source source)
    {
        _source = source;

        // Prime the cannons.
        popFront();
    }

    private
    {
        // The current block in the stream.
        T _current;

        // Are we there yet?
        bool _empty = false;
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

    auto blocks = f.byBlock!Data;

    assert(equal(data, blocks));
    blocks.popFront();
    assert(blocks.empty);
    assert(!equal(data, blocks));
}
