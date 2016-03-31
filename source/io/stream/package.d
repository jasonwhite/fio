/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.stream;

public import io.stream.types;
public import io.stream.traits;
public import io.stream.shim;

import std.traits : isArray;

/**
 * Reads exactly the number of bytes requested from the stream. Throws
 * an exception if it cannot be done. Returns the filled buffer.
 *
 * Note that, because it can potentially take multiple system calls to
 * complete the read, the read is not guaranteed to be atomic with
 * respect to other reads.
 *
 * Throws: ReadException if the given buffer cannot be completely filled.
 */
T[] readExactly(Stream, T)(auto ref Stream stream, T[] buf)
    if (isSource!(Stream))
{
    ubyte[] byteBuf = cast(ubyte[])buf;

    size_t totalRead = 0;
    while (totalRead < byteBuf.length)
    {
        if (immutable n = stream.read(byteBuf[totalRead .. $]))
            totalRead += n;
        else
            throw new ReadException(
                    "Failed to fill entire buffer from stream"
                    );
    }

    return buf;
}

/**
 * Writes exactly the given buffer and no less. Throws an exception if
 * it cannot be done.
 *
 * Note that, because it can potentially take multiple system calls to
 * complete the write, the write is not guaranteed to be atomic with
 * respect to other writes.
 *
 * Throws: WriteException if the given buffer cannot be completely written.
 */
void writeExactly(Stream, T)(auto ref Stream stream, in T[] buf)
    if (isSink!Stream)
{
    const(ubyte)[] byteBuf = cast(const(ubyte)[])buf;

    size_t total = 0;

    while (total < byteBuf.length)
    {
        if (immutable n = stream.write(byteBuf[total .. $]))
            total += n;
        else
            throw new WriteException(
                    "Failed to write entire buffer to stream"
                    );
    }
}

// Ditto
void writeExactly(Stream, T)(auto ref Stream stream, const auto ref T value)
    if (!isArray!T)
{
    write((cast(ubyte*)&value)[0 .. T.sizeof]);
}

/**
 * Reads the rest of the stream.
 */
T[] readAll(T=ubyte, Stream)(auto ref Stream stream, long upTo = long.max)
    if (isSource!Stream && isSeekable!Stream)
{
    import std.algorithm : min;
    import std.array : uninitializedArray;

    immutable remaining = min((stream.length - stream.position)/T.sizeof, upTo);

    auto buf = uninitializedArray!(T[])(remaining);

    immutable bytesRead = stream.read(buf);

    return buf[0 .. bytesRead/T.sizeof];
}

/**
 * Set the position (in bytes) of a stream.
 */
@property void position(Stream)(auto ref Stream stream, long offset)
    if (isSeekable!Stream)
{
    stream.seekTo(offset, From.start);
}

/**
 * Gets the position (in bytes) of a stream.
 */
@property auto position(Stream)(auto ref Stream stream)
    if (isSeekable!Stream)
{
    return stream.seekTo(0, From.here);
}

/**
 * Skip the specified number of bytes forward or backward.
 *
 * Returns: The position (in bytes) in the stream after the seek.
 */
long skip(Stream)(auto ref Stream stream, long offset)
    if (isSeekable!Stream)
{
    return stream.seekTo(offset, From.here);
}
