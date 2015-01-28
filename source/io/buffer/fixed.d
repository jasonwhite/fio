/**
 * Copyright: Copyright Jason White, 2013-
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 *
 * Description:
 * Buffers a stream using a fixed size buffer.
 */
module io.buffer.fixed;

import io.stream;
import io.buffer.traits;


class FixedBuffer(Stream, Access access = Access.all)
    if (isBufferable!(Stream, access))
{
    private
    {
        enum bufferReads = isSource!Stream &&
            (access & Access.read) == Access.read;
        enum bufferWrites = isSink!Stream &&
            (access & Access.write) == Access.write;
    }

    // The underlying stream.
    Stream stream;

    alias stream this;

    // Buffer to store the data to be read or written.
    private void[] _buffer;

    this(Stream stream, size_t bufSize = 8192)
    {
        this.stream = stream;
        _buffer.length = bufSize;
    }

    this(Stream stream, void[] buffer)
    {
        this.stream = stream;
        _buffer = buffer;
    }

    static if (bufferReads)
    {
        // Length of valid data in the buffer.
        private void[] _window;

        private size_t readPartial(void[] buf)
        {
            import std.algorithm : min;

            // Satisfy what can be copied so far from the buffer.
            immutable satisfiable = min(_window.length, buf.length);
            if (satisfiable > 0)
            {
                buf[0 .. satisfiable] = _window[0 .. satisfiable];
                _window = _window[satisfiable .. $];
            }

            return satisfiable;
        }

        size_t read(void[] buf)
        {
            beginRead();

            immutable satisfied = readPartial(buf);
            if (satisfied == buf.length)
                return satisfied;

            buf = buf[satisfied .. $];

            // Large read? Get it directly from the stream.
            if (buf.length >= _buffer.length)
                return stream.read(buf);

            // Buffer is empty, fill it back up.
            fill();

            // Finish the copy
            return satisfied + readPartial(buf);
        }

        /**
         * Fills the buffer with data.
         */
        void fill()
        {
            immutable bytesRead = stream.read(_buffer);
            _window = _buffer[0 .. bytesRead];
        }

        /**
         * Initiates a read. This handles flushing any data previously written.
         */
        static if (bufferWrites)
        {
            void beginRead()
            {
                if (_position == 0) return;
                flush();
            }
        }
        else
        {
            // Nothing to do, this should be optimized away.
            void beginRead() {}
        }
    }

    static if (bufferWrites)
    {
        // Current position in the buffer.
        private size_t _position;

        // Write part of the buffer.
        private size_t writePartial(in void[] buf)
        {
            import std.algorithm : min;

            immutable satisfiable = min(_buffer.length - _position, buf.length);
            if (satisfiable > 0)
            {
                _buffer[0 .. satisfiable] = buf[0 .. satisfiable];
                _position += satisfiable;
            }

            return satisfiable;
        }

        size_t write(const(void)[] buf)
        {
            beginWrite();

            immutable satisfied = writePartial(buf);
            if (satisfied == buf.length)
                return satisfied;

            buf = buf[satisfied .. $];

            // Buffer is full and there is more to write. Flush it.
            flush();

            // Large write? Push it directly to the stream.
            if (buf.length >= _buffer.length)
                return stream.write(buf);

            // Write the rest.
            return satisfied + writePartial(buf);
        }

        /**
         * Flushes all the data from the buffer.
         */
        void flush()
        {
            stream.write(_buffer[0 .. _position]);
            _position = 0;
        }

        /**
         * Initiates a write. This will handle seeking to the correct position
         * due to a previous read.
         */
        static if (bufferReads)
        {
            void beginWrite()
            {
                if (_window.length == 0) return;

                // The length of the window indicates how much data hasn't
                // "really" been read from the stream. Just seek backwards that
                // distance.
                stream.skip(-_window.length);
            }
        }
        else
        {
            // Nothing to do, this should be optimized away.
            void beginWrite() {}
        }
    }

    static if (isSeekable!Stream)
    {
        ptrdiff_t seekTo(ptrdiff_t offset, From from = From.start)
        {
            static if (bufferReads)
            {
                // Invalidate the window
                _window = _buffer[0 .. 0];
            }

            static if (bufferWrites)
            {
                flush();
            }

            return stream.seekTo(offset, from);
        }
    }
}

/**
 * Convenience function to create a fixed-sized buffer.
 */
@property auto fixedBuffer(Stream)
    (Stream stream, size_t bufSize = 8192)
    if (isBufferable!(Stream))
{
    return new FixedBuffer!(Stream)(stream, bufSize);
}

/// Ditto
@property auto fixedBuffer(Access access, Stream)
    (Stream stream, size_t bufSize = 8192)
    if (isBufferable!(Stream, access))
{
    return new FixedBuffer!(Stream, access)(stream, bufSize);
}

unittest
{
    import io.file.temp;

    auto f = tempFile().fixedBuffer;

    immutable data = "The quick brown fox jumps over the lazy dog.";
    char buffer[data.length];
    assert(f.write(data) == data.length);
    f.position = 0;
    assert(f.read(buffer) == buffer.length);
    assert(buffer == data);
}
