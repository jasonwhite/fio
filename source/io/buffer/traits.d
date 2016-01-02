/**
 * Copyright: Copyright Jason White, 2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.buffer.traits;

import io.stream.types;


/**
 * Checks if the stream can be buffered. A stream that is exclusively read from
 * or written to can always be buffered. However, when both reads and writes
 * must be buffered, the stream must also be seekable. There are no exceptions
 * to this last rule when buffering.
 */
enum isBufferable(Stream) = (isSource!Stream ^ isSink!Stream) ||
    isSeekable!Stream;

unittest
{
    interface A : Source {}
    static assert(isBufferable!A);

    interface B : Sink {}
    static assert(isBufferable!B);

    // Not possible. Stream must be seekable.
    interface C : SourceSink {}
    static assert(!isBufferable!C);

    interface D : Seekable!SourceSink {}
    static assert(isBufferable!D);

    interface E : Seekable!Source {}
    static assert(isBufferable!E);

    interface F : Seekable!Sink {}
    static assert(isBufferable!F);
}

/**
 * Checks if the stream can be flushed.
 */
enum isFlushable(Stream) =
    is(typeof({
        Stream s = void;
        s.flush();
    }));

unittest
{
    struct A {}
    static assert(!isFlushable!A);

    struct B { void flush(); }
    static assert(isFlushable!B);
}
