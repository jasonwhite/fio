/**
 * Copyright: Copyright Jason White, 2014
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.stream;


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
 * must define the member function $(D read).
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

    static struct B {
        size_t read(void[] buf) { return buf.length; }
    }
    static assert(isSource!B);

    static struct C {
        void read() {}
    }
    static assert(!isSource!C);
}

/**
 * Checks if a type is a sink. A sink is a stream that can be written to and must
 * define the member function $(D write).
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

    static struct B {
        size_t write(in ubyte[] data) { return 0; }
    }
    static assert(isSink!B);

    static struct C {
        void write() {}
    }
    static assert(!isSink!C);
}

/**
 * Checks if a type is seekable. A seekable stream must define the member
 * function $(D seek).
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
        size_t seekTo(ptrdiff_t offset, From from) { return 0; }
    }
    static assert(isSeekable!B);

    static struct C {
        // Should return the current position.
        void seekTo(ptrdiff_t offset, From from) {}
    }
    static assert(!isSeekable!C);
}

/**
 * Set the position (in bytes) of a stream. The stream must be seekable.
 *
 * Params:
 *   stream = The stream to set the position of.
 *   offset = The offset into the stream.
 */
@property void position(Stream, Offset)(auto ref Stream stream, Offset offset)
    if (isSeekable!Stream)
{
    stream.seekTo(offset, From.start);
}

/**
 * Get the position (in bytes) of a stream. The stream must be seekable.
 *
 * Params:
 *   stream = The stream to set the position of.
 */
@property auto position(Stream)(auto ref Stream stream)
    if (isSeekable!Stream)
{
    return stream.seekTo(0, From.here);
}

/**
 * Skip the specified number of bytes forward or backward. The stream must be
 * seekable.
 */
auto skip(Stream, Offset)(auto ref Stream stream, Offset offset)
    if (isSeekable!Stream)
{
    return stream.seekTo(offset, From.here);
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
    size_t write(in void[] data)
    {
        return data.length;
    }
}

unittest
{
    auto s = NullStream();

    static assert(
         isSource!NullStream &&
         isSink!NullStream &&
        !isSeekable!NullStream
        );

    // Reading
    ubyte[6] buf = [4, 8, 15, 16, 23, 42];
    assert(s.read(buf) == buf.length);
    assert(buf == [0, 0, 0, 0, 0, 0]);

    // Writing
    assert(s.write(buf) == buf.length);
}

/**
 * Reads exactly the number of bytes requested from the stream. Throws an
 * exception if it cannot be done. Returns the number of bytes read.
 *
 * Throws: ReadException if the given buffer cannot be completely filled.
 */
auto readExactly(Source)(auto ref Source source, void[] buf)
    if (isSource!Source)
{
    immutable bytesRead = source.read(buf);
    if (bytesRead != buf.length)
        throw new ReadException("Failed to fill entire buffer from stream");

    return bytesRead;
}

/**
 * Writes exactly the given buffer and no less. Throws an exception if it cannot
 * be done. Returns the number of bytes written.
 *
 * Throws: WriteException if the given buffer cannot be completely written.
 */
auto writeExactly(Sink)(auto ref Sink sink, in void[] buf)
    if (isSink!Sink)
{
    immutable bytesWritten = sink.write(buf);
    if (bytesWritten != buf.length)
        throw new WriteException("Failed to write entire buffer to stream");

    return bytesWritten;
}

/**
 * Copies a single block from the source to the sink. The number of bytes copied
 * is returned.
 */
private size_t copyBlock(Source, Sink)
    (auto ref Source source, auto ref Sink sink, ubyte[] buf)
    if (isSource!Source && isSink!Sink)
{
    size_t bytesRead = source.read(buf);
    size_t bytesWritten = sink.write(buf[0 .. bytesRead]);
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
size_t copyTo(Source, Sink)(auto ref Source source, auto ref Sink sink,
        ubyte[] buf, size_t n = size_t.max/2-1)
    if (isSource!Source && isSink!Sink)
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
size_t copyTo(Source, Sink, size_t BufSize = 4096)
    (auto ref Source source, auto ref Sink sink, size_t n = size_t.max/2-1)
    if (isSource!Source && isSink!Sink)
{
    ubyte[BufSize] buffer;
    return source.copyTo(sink, n);
}

unittest
{
    // TODO
}
