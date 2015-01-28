/**
 * Copyright: Copyright Jason White, 2013-
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.buffer.traits;

import io.traits;

/**
 * Checks if the stream can be buffered. The requirements for buffering a stream
 * depend on the desired access to the stream. A stream that is exclusively
 * read from or written to can always be buffered. However, when both reads and
 * writes must be buffered, the stream must also be seekable. There are no
 * exceptions to this last rule when buffering.
 */
template isBufferable(Stream, Access mask = Access.read)
{
    static if ((mask & Access.readWrite) == Access.readWrite)
        static if (isSource!Stream && isSink!Stream)
            enum isBufferable = isSeekable!Stream;
        else
            enum isBufferable = isSource!Stream ^ isSink!Stream;
    else static if ((mask & Access.read) == Access.read)
        enum isBufferable = isSource!Stream;
    else static if ((mask & Access.write) == Access.write)
        enum isBufferable = isSink!Stream;
    else
        enum isBufferable = false;
}

unittest
{
    static struct A
    {
        size_t read(void[] data) { return 0; }
    }

    static assert(isBufferable!(A, Access.read));
    static assert(!isBufferable!(A, Access.write));
    static assert(isBufferable!(A, Access.readWrite));
    static assert(isBufferable!(A, Access.all));

    static struct B
    {
        size_t write(const(void)[] data) { return 0; }
    }

    static assert(!isBufferable!(B, Access.read));
    static assert(isBufferable!(B, Access.write));
    static assert(isBufferable!(B, Access.readWrite));
    static assert(isBufferable!(B, Access.all));

    static struct C
    {
        size_t read(void[] data) { return 0; }
        size_t write(const(void)[] data) { return 0; }
    }

    static assert(isBufferable!(C, Access.read));
    static assert(isBufferable!(C, Access.write));
    static assert(!isBufferable!(C, Access.readWrite));
    static assert(!isBufferable!(C, Access.all));

    static struct D
    {
        size_t write(const(void)[] data) { return 0; }
        size_t read(void[] data) { return 0; }
        ptrdiff_t seekTo(ptrdiff_t offset, From from);
    }

    static assert(isBufferable!(D, Access.read));
    static assert(isBufferable!(D, Access.write));
    static assert(isBufferable!(D, Access.readWrite));
    static assert(isBufferable!(D, Access.all));
}
