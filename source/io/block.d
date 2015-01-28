/**
 * Copyright: Copyright Jason White, 2013-
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
struct Block(T, Stream)
    if (isSource!Stream || isSink!Stream)
{
    Stream stream;

    this(Stream s)
    {
        this.stream = s;

        static if (isSource!Stream)
        {
            // Prime the cannons.
            popFront();
        }
    }

    static if (isSource!Stream)
    {
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
            immutable n = stream.read((&_current)[0 .. 1]);

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

    static if (isSink!Stream)
    {
        /**
         * Writes a block to the stream. Throws an exception if the entire block
         * cannot be written.
         *
         * Throws: WriteException
         */
        void put()(const auto ref T block)
        {
            stream.writeExactly((&block)[0 .. 1]);
        }

        /**
         * Writes multiple blocks to the stream. Throws an exception if all of
         * the blocks could not be written.
         *
         * Throws: WriteException
         */
        void put(in T[] blocks)
        {
            stream.writeExactly(blocks);
        }
    }
}

/**
 * Helper function for constructing a block range.
 */
@property auto byBlock(T, Stream)(Stream stream)
    if (isSource!Stream || isSink!Stream)
{
    return Block!(T, Stream)(stream);
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

    auto blocks = tempFile.byBlock!Data;

    blocks.put(data);

    blocks.stream.position = 0;
    blocks.popFront();

    assert(equal(data, blocks));
    assert(!equal(data, blocks));
}
