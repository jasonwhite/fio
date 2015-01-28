/**
 * Copyright: Copyright Jason White, 2014
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.stream;

import io.traits;

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

    /**
     * Reads exactly the number of bytes requested from the stream. Throws an
     * exception if it cannot be done. Returns the number of bytes read.
     *
     * Throws: ReadException if the given buffer cannot be completely filled.
     */
    final size_t readExactly(void[] buf)
    {
        immutable bytesRead = read(buf);
        if (bytesRead != buf.length)
            throw new ReadException("Failed to fill entire buffer from stream");

        return bytesRead;
    }
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
    size_t write(in void[] data);

    /**
     * Writes exactly the given buffer and no less. Throws an exception if it cannot
     * be done. Returns the number of bytes written.
     *
     * Throws: WriteException if the given buffer cannot be completely written.
     */
    final size_t writeExactly(in void[] buf)
    {
        immutable bytesWritten = write(buf);
        if (bytesWritten != buf.length)
            throw new WriteException("Failed to write entire buffer to stream");

        return bytesWritten;
    }
}

/**
 * A seekable stream can move the read/write starting position in the stream.
 */
interface Seekable
{
    alias Offset = long;

    /**
     * Seeks to the specified offset relative to the given starting location.
     *
     * Params:
     *   offset = The offset relative to $(D from).
     *   from = The relative position to seek to.
     */
    Offset seekTo(Offset offset, From from = From.start);

    /**
     * Set the position (in bytes) of a stream.
     *
     * Params:
     *   offset = The offset into the stream.
     */
    final @property void position(Offset offset)
    {
        seekTo(offset, From.start);
    }

    /**
     * Get the position (in bytes) of a stream.
     */
    final @property Offset position()
    {
        return seekTo(0, From.here);
    }

    /**
     * Skip the specified number of bytes forward or backward.
     */
    final Offset skip(Offset offset)
    {
        return seekTo(offset, From.here);
    }
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
class NullStream : Source, Sink
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
    static assert(
         isSource!NullStream &&
         isSink!NullStream &&
        !isSeekable!NullStream
        );

    auto s = new NullStream();

    // Reading
    ubyte[6] buf = [4, 8, 15, 16, 23, 42];
    assert(s.read(buf) == buf.length);
    assert(buf == [0, 0, 0, 0, 0, 0]);

    // Writing
    assert(s.write(buf) == buf.length);
}

version (none):

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
