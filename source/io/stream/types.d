/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.stream.types;

/**
 * Checks if a type is a source. A source is a stream that can be read from and
 * must define the member function $(D read). The stream can be either a class
 * or a struct.
 */
enum isSource(Stream) =
    is(typeof({
        Stream s = void;
        void[] buf;
        ulong n = s.read(buf);
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
        immutable size_t[] data;
        ulong n = s.put(data);
    }));

unittest
{
    static struct A {}
    static assert(!isSink!A);

    static struct B
    {
        size_t put(const(void)[] data) { return 0; }
    }

    static assert(isSink!B);

    static struct C
    {
        void put() {}
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
        size_t put(const(void)[] data) { return 0; }
    }

    static assert(!isSourceSink!A);

    static struct B
    {
        size_t put(const(void)[] data) { return 0; }
        size_t read(void[] buf) { return buf.length; }
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
        size_t put(const(void)[] data) { return 0; }
    }

    static assert(isStream!A);

    static struct B
    {
        size_t read(void[] buf) { return buf.length; }
    }

    static assert(isStream!B);

    static struct C
    {
        long seekTo(long offset, From from) { return 0; }
    }

    static assert(!isStream!C);
}

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
 * Stream exceptions.
 */
class StreamException : Exception       { this(string msg) { super(msg); } }

/// Ditto
class ReadException   : StreamException { this(string msg) { super(msg); } }

/// Ditto
class WriteException  : StreamException { this(string msg) { super(msg); } }

/// Ditto
class SeekException   : StreamException { this(string msg) { super(msg); } }

/**
 * A source is a stream that can be read from.
 */
interface Source
{
    /**
     * Reads data into the specified buffer. The number of bytes read is
     * returned.
     */
    size_t read(void[] buf);
}

unittest
{
    static assert( isSource!Source);
    static assert(!isSink!Source);
    static assert(!isSeekable!Source);
}

/**
 * A sink is a stream that can be written to.
 */
interface Sink
{
    /**
     * Writes data to the stream. The number of bytes successfully written is
     * returned.
     */
    size_t put(const(void)[] data);

    /// Ditto
    alias write = put;
}

unittest
{
    static assert(!isSource!Sink);
    static assert( isSink!Sink);
    static assert(!isSeekable!Sink);
}

/**
 * A stream that is both a Source and a Sink.
 */
interface SourceSink : Source, Sink {}

/**
 * A seekable stream can move the read/write starting position in the stream.
 */
interface Seekable(Stream) : Stream
{
    /**
     * Seeks to the specified offset relative to the given starting location.
     *
     * Params:
     *   offset = The offset relative to $(D from).
     *   from = The relative position to seek to.
     */
    long seekTo(long offset, From from = From.start);
}

unittest
{
    static assert( isSource!(Seekable!Source));
    static assert( isSink!(Seekable!Sink));
    static assert( isSource!(Seekable!SourceSink));
    static assert( isSink!(Seekable!SourceSink));
    static assert(!isSource!(Seekable!Sink));
    static assert(!isSink!(Seekable!Source));
    static assert( isSeekable!(Seekable!Source));
    static assert( isSeekable!(Seekable!Sink));
    static assert( isSeekable!(Seekable!SourceSink));
}

unittest
{
    static assert(is(Seekable!SourceSink : Source));
    static assert(is(Seekable!SourceSink : Sink));
    static assert(is(Seekable!Source : Source));
    static assert(is(Seekable!Sink : Sink));
    static assert(!is(Seekable!Source : Sink));
    static assert(!is(Seekable!Sink : Source));
}

/**
 * A stream implementation of /dev/null.
 *
 * A stream that does nearly nothing. Reads return zero's and writes get sucked
 * into a black hole.
 *
 * This stream serves two purposes: to act as a reference and to be used in unit
 * tests.
 */
struct NullStream
{
    /**
     * Fills the buffer with zeros.
     */
    size_t read(void[] buf)
    {
        foreach (ref e; cast(ubyte[])buf)
            e = e.init;

        return buf.length;
    }

    /**
     * Simply returns the length of the data array.
     */
    size_t put(const(void)[] data)
    {
        return data.length;
    }
}

unittest
{
    static assert(isSourceSink!NullStream);
}

unittest
{
    auto s = NullStream();

    // Reading
    ubyte[6] buf = [4, 8, 15, 16, 23, 42];
    assert(s.read(buf) == buf.length);
    assert(buf == [0, 0, 0, 0, 0, 0]);

    // Writing
    assert(s.put(buf) == buf.length);
}

version (none):

/**
 * Copies a single block from the source to the sink. The number of bytes copied
 * is returned.
 */
private size_t copyBlock(Source source, Sink sink, ubyte[] buf)
{
    size_t bytesRead = source.read(buf);
    size_t bytesWritten = sink.put(buf[0 .. bytesRead]);
    copied += bytesWritten;
    if (bytesWritten != bytesRead)
    {
        // Uh oh. We read data that we failed to write. The source is now
        // in an incorrect position. Seek back to the correct position if we
        // can. Otherwise, throw an exception.
        static if (isSeekable!Source)
        {
            source.skip(bytesWritten - bytesRead);
        }
        else
        {
            throw new WriteException(
                "Failed to fully copy data from the source stream to the sink "
                "stream. (The current read offset in the source is greater "
                "than the number of bytes copied to the sink.)"
                );
        }
    }

    return bytesWritten;
}

unittest
{
    // TODO
}

/**
 * Copies the rest of the source stream to the sink, up to the given number of
 * bytes. The positions of both streams are advanced according to how much is
 * copied. The number of copied bytes is returned.
 */
size_t copyTo(Source source, Sink sink,
        ubyte[] buf, size_t n = size_t.max/2-1)
{
    size_t total;
    size_t copied;

    // Maximum number of blocks to write.
    size_t blocks = n / buf.length;

    for (size_t i = 0; i < blocks; i++)
    {
        copied = source.copyBlock(sink, buf);
        total += copied;
        if (copied < buf.length)
            return total;
    }

    // Copy what is left-over.
    total += source.copyBlock(sink, buf[0 .. n % buf.length]);

    return total;
}

/// Ditto
size_t copyTo(size_t BufSize = 4096)
    (Source source, Sink sink, size_t n = size_t.max/2-1)
{
    ubyte[BufSize] buffer;
    return source.copyTo(sink, n);
}

unittest
{
    // TODO
}
