/**
 * Copyright: Copyright Jason White, 2015
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.traits;


/**
 * Specifies how to access a stream.
 */
enum Access
{
    /// Default access. Not very useful.
    none = 0,

    /// Allows only read operations on the stream.
    read = 1 << 0,

    /// Allows only write operations on the stream.
    write = 1 << 1,

    /// Allows data to be executed. This is only used for memory mapped files.
    execute = 1 << 2,

    /// Allows both read and write operations on the stream.
    readWrite = read | write,

    /// Complete access.
    all = read | write | execute,
}

/**
 * Relative position to seek from.
 */
enum From
{
    /// Seek relative to the beginning of the stream.
    start,

    /// Seek relative to the current position in the stream.
    here,

    /// Seek relative to the end of the stream.
    end,
}

/**
 * Checks if a type is a source. A source is a stream that can be read from and
 * must define the member function $(D read). The stream can be either a class
 * or a struct.
 */
enum isSource(Stream) =
    is(typeof({
        Stream s = void;
        size_t[] buf;
        auto n = s.read(buf);
    }));

unittest
{
    static struct A {}
    static assert(!isSource!A);

    static struct B
    {
        size_t read(void[] buf) { return buf.length; }
    }

    static assert(isSource!B);

    static struct C
    {
        void read() {}
    }

    static assert(!isSource!C);
}

/**
 * Checks if a type is a sink. A sink is a stream that can be written to and must
 * define the member function $(D write). The stream can be either a class or a
 * struct.
 */
enum isSink(Stream) =
    is(typeof({
        Stream s = void;
        immutable ubyte[] data = [1, 2, 3];
        auto n = s.write(data);
    }));

unittest
{
    static struct A {}
    static assert(!isSink!A);

    static struct B
    {
        size_t write(in ubyte[] data) { return 0; }
    }

    static assert(isSink!B);

    static struct C
    {
        void write() {}
    }

    static assert(!isSink!C);
}

/**
 * Checks if a type is seekable. A seekable stream must define the member
 * function $(D seek). The stream can be either a class or a struct.
 */
enum isSeekable(Stream) =
    is(typeof({
        Stream s = void;
        auto pos = s.seekTo(0, From.start);
    }));

unittest
{
    static struct A {}
    static assert(!isSeekable!A);

    static struct B {
        long seekTo(long offset, From from) { return 0; }
    }
    static assert(isSeekable!B);

    static struct C {
        // Should return the current position.
        void seekTo(long offset, From from) {}
    }
    static assert(!isSeekable!C);
}
