/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.stream.shim;

import io.stream.traits;
import io.stream.types;

/**
 * Wraps a stream to provide useful higher-level functions.
 */
struct StreamShim(Stream)
    if (isStream!Stream)
{
    Stream stream;

    alias stream this;

    alias Offset = Stream.Offset;

    /**
     * Copying is disabled. Reference counting should be used instead.
     */
    @disable this(this);

    /**
     * Forwards arguments to super class.
     */
    this(T...)(auto ref T args)
    {
        import std.functional : forward;
        stream = Stream(forward!args);
    }

    static if (isSource!Stream)
    {
        /**
         * Fills the given buffer with data from the stream.
         *
         * Note: This is not guaranteed to read the entire buffer from the
         * stream.  If $(D T.sizeof) is larger than 1, it is possible that an
         * element is partially read. If a guarantee that the entire buffer is
         * filled, use $(D readExactly) instead.
         *
         * Returns: The number of bytes read.
         */
        size_t read(T)(T[] buf)
        {
            return stream.read(cast(ubyte[])buf);
        }
    }

    static if (isSink!Stream)
    {
        /**
         * Writes an array of type T to the stream.
         *
         * Returns: The number of bytes written.
         *
         * Note: This is not guaranteed to write the entire buffer to the
         * stream. If $(D T.sizeof) is larger than 1, it is possible that an
         * element may not be fully written. If the guarantee that the entire
         * buffer is written to the stream, use $(D writeExactly) instead.
         */
        size_t write(T)(in T[] buf)
        {
            return stream.write(cast(const(ubyte)[])buf);
        }

        alias put = write;
    }
}
