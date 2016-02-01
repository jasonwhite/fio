/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.stream.traits;

import io.stream.types : From;

/**
 * Checks if a type is a source. A source is a stream that can be read from and
 * must define the member function $(D read). The stream can be either a class
 * or a struct.
 */
enum isSource(Stream) =
    is(typeof({
        Stream s = void;
        ubyte[] buf;
        ulong n = s.read(buf);
    }));

unittest
{
    static struct A {}
    static assert(!isSource!A);

    static struct B
    {
        size_t read(ubyte[] buf) { return buf.length; }
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
        immutable ubyte[] data;
        ulong n = s.write(data);
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

/**
 * Checks if the type is both a source and a sink.
 */
enum isSourceSink(Stream) = isSource!Stream && isSink!Stream;

unittest
{
    static struct A
    {
        size_t write(in ubyte[] data) { return 0; }
    }

    static assert(!isSourceSink!A);

    static struct B
    {
        size_t write(in ubyte[] data) { return 0; }
        size_t read(ubyte[] buf) { return buf.length; }
    }

    static assert(isSourceSink!B);
}

/**
 * Checks if the type is either a source or a sink (i.e., a stream).
 */
enum isStream(Stream) = isSource!Stream || isSink!Stream;

unittest
{
    static struct A
    {
        size_t write(in ubyte[] data) { return 0; }
    }

    static assert(isStream!A);

    static struct B
    {
        size_t read(ubyte[] buf) { return buf.length; }
    }

    static assert(isStream!B);

    static struct C
    {
        long seekTo(long offset, From from) { return 0; }
    }

    static assert(!isStream!C);
}
