/**
 * Copyright: Copyright Jason White, 2015
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.buffer.traits;

import io.stream : Source, Sink, Seekable;


/**
 * Checks if the stream can be buffered. A stream that is exclusively read from
 * or written to can always be buffered. However, when both reads and writes
 * must be buffered, the stream must also be seekable. There are no exceptions
 * to this last rule when buffering.
 */
template isBufferable(Stream)
{
    static if (is(Stream : Source) && is(Stream : Sink))
        enum isBufferable = is(Stream : Seekable);
    else
        enum isBufferable = is(Stream : Source) ^ is(Stream : Sink);
}

unittest
{
    // Okay
    interface A : Source {}
    static assert(isBufferable!A);

    // Okay
    interface B : Sink {}
    static assert(isBufferable!B);

    // Impossible! Stream must be seekable.
    interface C : Source, Sink {}
    static assert(!isBufferable!C);

    // Okay. It's also seekable.
    interface D : Source, Sink, Seekable {}
    static assert(isBufferable!D);
}

/**
 * Interface for all types of buffers.
 */
interface Buffered(Stream)
    if (isBufferable!Stream)
{
    static if (is(Stream : Sink))
    {
        /**
         * Writes buffered data to the underlying stream.
         */
        void flush();
    }
}
