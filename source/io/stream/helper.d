/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.stream.helper;

import io.stream.primitives;

import std.traits;

/**
 * Wraps a stream to provide useful higher-level functions.
 */
struct StreamHelper(Stream)
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

        /**
         * Reads exactly the number of bytes requested from the stream. Throws
         * an exception if it cannot be done. Returns the filled buffer.
         *
         * Throws: ReadException if the given buffer cannot be completely filled.
         */
        T[] readExactly(T)(T[] buf)
        {
            ubyte[] byteBuf = cast(ubyte[])buf;

            if (stream.read(byteBuf) != byteBuf.length)
                throw new ReadException("Failed to fill entire buffer from stream");

            return buf;
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

        /**
         * Writes exactly the given buffer and no less. Throws an exception if
         * it cannot be done.
         *
         * Throws: WriteException if the given buffer cannot be completely written.
         */
        void writeExactly(T)(in T[] buf)
            if (isSink!Stream)
        {
            const(ubyte)[] byteBuf = cast(const(ubyte)[])buf;
            if (stream.write(byteBuf) != byteBuf.length)
                throw new WriteException("Failed to write entire buffer to stream");
        }

        // Ditto
        void writeExactly(T)(const auto ref T value)
            if (!isArray!T)
        {
            write((&value)[0 .. 1]);
        }

        alias put = write;
    }

    static if (isSeekable!Stream)
    {
        /**
         * Set the position (in bytes) of a stream.
         */
        @property void position(Offset offset)
        {
            stream.seekTo(offset, From.start);
        }

        /**
         * Get the position (in bytes) of a stream.
         */
        @property Offset position()
        {
            return stream.seekTo(0, From.here);
        }

        /**
         * Skip the specified number of bytes forward or backward.
         */
        Offset skip(Offset offset)
        {
            return stream.seekTo(offset, From.here);
        }
    }

    static if (isSource!Stream && isSeekable!Stream)
    {
        /**
         * Reads the rest of the stream.
         */
        T[] readAll(T=ubyte)(Offset upTo = long.max)
        {
            import std.algorithm : min;
            import std.array : uninitializedArray;

            immutable remaining = min((stream.length - stream.position)/T.sizeof, upTo);

            auto buf = uninitializedArray!(T)(remaining);

            immutable bytesRead = stream.read(buf);

            return buf[0 .. bytesRead/T.sizeof];
        }
    }
}
