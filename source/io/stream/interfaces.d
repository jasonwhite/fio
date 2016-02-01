/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.stream.interfaces;

import io.stream.traits;

/**
 * A source is a stream that can be read from.
 */
interface Source
{
    /**
     * Reads data into the specified buffer. The number of bytes read is
     * returned.
     */
    size_t read(ubyte[] buf);
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
    size_t write(in ubyte[] data);

    /// Ditto
    alias put = write;
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
