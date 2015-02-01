/**
 * Copyright: Copyright Jason White, 2015-
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 *
 * Description:
 * Buffers a stream using a fixed-size buffer.
 */
module io.buffer.fixed;

import io.stream;
import io.buffer.traits;

class FixedBuffer(Stream) : Stream
{
    // Buffer to store the data to be read or written.
    private void[] _buffer;

    // Current read/write position in the buffer. For writes, this is >0 if data
    // has been written to the buffer but not flushed.
    private size_t _position;

    /**
     * Forwards arguments to super class.
     */
    this(T...)(auto ref T args)
    {
        import std.algorithm : forward;
        super(forward!args);
        _buffer.length = 8192;
    }

    /**
     * Upon destruction, any pending writes are flushed to the underlying
     * stream.
     */
    ~this()
    {
        static if (is(Stream : Sink))
            flush();
    }

    /**
     * Sets the size of the buffer. The default is 8192 bytes. This will only
     * succeed if no data has been buffered (e.g., just after construction).
     */
    @property void bufferSize(size_t size)
    {
        if (_position > 0) return;

        static if (is(Stream : Source))
        {
            if (_valid > 0) return;
        }

        _buffer.length = size;
    }

    /**
     * Gets the current buffer size. The default is 8192 bytes.
     */
    @property size_t bufferSize()
    {
        return _buffer.length;
    }

    static if (is(Stream : Source))
    {
        // Last valid position in the buffer. This is 0 if no read data is
        // sitting in the buffer.
        private size_t _valid;

        /**
         * Initiates a read. This handles flushing any data previously written.
         */
        static if (is(Stream : Sink))
        {
            private void beginRead()
            {
                if (_position > 0)
                    flush();
            }
        }
        else
        {
            // Nothing to do, this should be optimized away.
            private void beginRead() {}
        }

        private size_t readPartial(void[] buf)
        {
            import std.algorithm : min;

            // Satisfy what can be copied so far from the buffer.
            immutable satisfiable = min(_valid - _position, buf.length);
            buf[0 .. satisfiable] = _buffer[_position .. _position + satisfiable];
            _position += satisfiable;

            return satisfiable;
        }

        /**
         * Reads data from the stream into the given buffer. The number of bytes
         * read is returned.
         */
        override size_t read(void[] buf)
        {
            beginRead();

            immutable satisfied = readPartial(buf);
            if (satisfied == buf.length)
                return satisfied;

            buf = buf[satisfied .. $];

            // Large read? Get it directly from the stream.
            if (buf.length >= _buffer.length)
                return satisfied + super.read(buf);

            // Buffer is empty, fill it back up.
            immutable bytesRead = super.read(_buffer);
            _position = 0;
            _valid = bytesRead;

            // Finish the copy
            return satisfied + readPartial(buf);
        }
    }

    static if (is(Stream : Sink))
    {
        /**
         * Initiates a write. This will handle seeking to the correct position
         * due to a previous read.
         */
        static if (is(Stream : Source))
        {
            private void beginWrite()
            {
                if (_valid == 0) return;

                // The length of the window indicates how much data hasn't
                // "really" been read from the stream. Just seek backwards that
                // distance.
                super.skip(_position - _valid);
                _position = _valid = 0;
            }
        }
        else
        {
            // Nothing to do. This should be optimized away.
            private void beginWrite() {}
        }

        /*
         * Copies as much as possible to the stream buffer. The number of bytes
         * copied is returned.
         */
        private size_t writePartial(in void[] buf)
        {
            import std.algorithm : min;

            immutable satisfiable = min(_buffer.length - _position, buf.length);
            _buffer[_position .. _position + satisfiable] = buf[0 .. satisfiable];
            _position += satisfiable;

            return satisfiable;
        }

        /**
         * Writes the given data to the buffered stream. When the internal
         * buffer is completely filled, it is flushed to the underlying stream.
         */
        override size_t write(const(void)[] buf)
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
                return satisfied + super.write(buf);

            // Write the rest.
            return satisfied + writePartial(buf);
        }

        /**
         * Writes any pending data to the underlying stream.
         */
        void flush()
        {
            if (_position > 0)
                _position -= super.write(_buffer[0 .. _position]);
        }
    }

    static if (is(Stream : Seekable))
    {
        /**
         * Seeks to the given position relative to the given starting point.
         */
        override ptrdiff_t seekTo(ptrdiff_t offset, From from = From.start)
        {
            static if (is(Stream : Source))
            {
                if (_valid > 0)
                {
                    if (from == From.here)
                    {
                        // Can we seek within the buffer?
                        if (_position + offset < _valid)
                        {
                            _position += offset;
                            return super.position + (_position - _valid);
                        }
                    }

                    // Invalidate the window
                    _position = _valid = 0;
                }
            }

            static if (is(Stream : Sink))
            {
                flush();
            }

            return super.seekTo(offset, from);
        }
    }
}

unittest
{
    import io.file.stream, io.file.temp;

    immutable data = "The quick brown fox jumps over the lazy dog.";
    char buffer[data.length];

    foreach (bufSize; [0, 1, 2, 8, 16, 64, 4096, 8192])
    {
        auto f = tempFile!(FixedBuffer!File);
        f.bufferSize = bufSize;
        assert(f.bufferSize == bufSize);

        assert(f.write(data) == data.length);
        f.position = 0;
        assert(f.read(buffer) == buffer.length);
        assert(buffer == data);
    }
}

unittest
{
    import io.file.stream;
    import std.typecons : scoped;

    auto tf = testFile();

    auto f = scoped!(FixedBuffer!File)(tf.name, FileFlags.writeNew);
    f.write("asdf");
}
