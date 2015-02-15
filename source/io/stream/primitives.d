/**
 * Copyright: Copyright Jason White, 2015
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.stream.primitives;

import io.stream.types;

import std.traits;

/**
 * Reads exactly the number of bytes requested from the stream. Throws an
 * exception if it cannot be done. Returns the number of bytes read.
 *
 * Throws: ReadException if the given buffer cannot be completely filled.
 */
auto readExactly(Stream)(Stream stream, void[] buf)
    if (isSource!Stream)
{
    immutable bytesRead = stream.read(buf);
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
auto writeExactly(Stream)(Stream stream, const(void)[] buf)
    if (isSink!Stream)
{
    immutable bytesWritten = stream.write(buf);
    if (bytesWritten != buf.length)
        throw new WriteException("Failed to write entire buffer to stream");

    return bytesWritten;
}

/// Ditto
auto writeExactly(Stream, T)(Stream stream, const auto ref T value)
    if (isSink!Stream && !isArray!T)
{
    return stream.writeExactly((&value)[0 .. 1]);
}

/// Ditto
alias put = writeExactly;


/**
 * Set the position (in bytes) of a stream.
 *
 * Params:
 *   offset = The offset into the stream.
 */
@property void position(Stream, Offset)(Stream stream, Offset offset)
    if (isSeekable!Stream)
{
    stream.seekTo(offset, From.start);
}

/**
 * Get the position (in bytes) of a stream.
 */
@property auto position(Stream)(Stream stream)
    if (isSeekable!Stream)
{
    return stream.seekTo(0, From.here);
}

/**
 * Skip the specified number of bytes forward or backward.
 */
auto skip(Stream, Offset)(Stream stream, Offset offset)
    if (isSeekable!Stream)
{
    return stream.seekTo(offset, From.here);
}
