/**
 * Copyright: Copyright Jason White, 2015
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.block;

import io.traits, io.stream;

/**
 * Wraps a stream in a range interface. It is assumed that the stream is
 * buffered such that performance is not adversely affected.
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
