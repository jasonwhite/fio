/**
 * Copyright: Copyright Jason White, 2015
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 *
 * Description:
 * Buffers a stream using a fixed-size buffer.
 */
module io.buffer.fixed;

import io.stream;
import io.buffer.traits;

struct FixedBufferBase(Stream)
    if (is(Stream == struct) && isBufferable!Stream)
{
    Stream stream;

    alias stream this;

    alias Offset = Stream.Offset;

    // Buffer to store the data to be read or written.
    private void[] _buffer;

    // Current read/write position in the buffer. For writes, this is >0 if data
    // has been written to the buffer but not flushed.
    private size_t _position;

    @disable this(this);

    /**
     * Forwards arguments to super class.
     */
    this(T...)(auto ref T args)
    {
        import std.functional : forward;
        stream = Stream(forward!args);
        _buffer.length = 8192;
    }

    /**
     * Upon destruction, any pending writes are flushed to the underlying
     * stream.
     */
    ~this()
    {
        static if (isSink!Stream)
            flush();
    }

    /**
     * Sets the size of the buffer. The default is 8192 bytes. This will only
     * succeed if no data has been buffered (e.g., just after construction).
     */
    @property void bufferSize(size_t size)
    {
        if (_position > 0) return;

        static if (isSource!Stream)
        {
            if (_valid > 0) return;
        }

        _buffer.length = size;
    }

    /**
     * Gets the current buffer size. The default is 8192 bytes.
     */
    @property size_t bufferSize() const pure nothrow
    {
        return _buffer.length;
    }

    static if (isSource!Stream)
    {
        // Last valid position in the buffer. This is 0 if no read data is
        // sitting in the buffer.
        private size_t _valid;

        /**
         * Initiates a read. This handles flushing any data previously written.
         */
        static if (isSink!Stream)
        {
            private void beginRead()
            {
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
        size_t read(void[] buf)
        {
            beginRead();

            immutable satisfied = readPartial(buf);
            if (satisfied == buf.length)
                return satisfied;

            buf = buf[satisfied .. $];

            // Large read? Get it directly from the stream.
            if (buf.length >= _buffer.length)
                return satisfied + stream.read(buf);

            // Buffer is empty, fill it back up.
            immutable bytesRead = stream.read(_buffer);
            _position = 0;
            _valid = bytesRead;

            // Finish the copy
            return satisfied + readPartial(buf);
        }
    }

    static if (isSink!Stream)
    {
        /**
         * Initiates a write. This will handle seeking to the correct position
         * due to a previous read.
         */
        static if (isSource!Stream)
        {
            private void beginWrite()
            {
                if (_valid == 0) return;

                // The length of the window indicates how much data hasn't
                // "really" been read from the stream. Just seek backwards that
                // distance.
                stream.skip(_position - _valid);
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
                return satisfied + stream.write(buf);

            // Write the rest.
            return satisfied + writePartial(buf);
        }

        alias put = write;

        /**
         * Writes any pending data to the underlying stream.
         */
        void flush()
        {
            static if (isSource!Stream)
            {
                if (_valid > 0)
                    return;
            }

            if (_position > 0)
            {
                stream.writeExactly(_buffer[0 .. _position]);
                _position = 0;
            }
        }
    }

    static if (isSeekable!Stream)
    {
        /**
         * Seeks to the given position relative to the given starting point.
         */
        Offset seekTo(Offset offset, From from = From.start)
        {
            static if (isSource!Stream)
            {
                if (_valid > 0)
                {
                    if (from == From.here)
                    {
                        // Can we seek within the buffer?
                        // FIXME: Handle potential integer overflow.
                        if (_position + offset < _valid)
                        {
                            _position += offset;
                            return stream.position + (_position - _valid);
                        }
                    }

                    // Invalidate the window
                    _position = _valid = 0;
                }
            }

            static if (isSink!Stream)
            {
                flush();
            }

            return stream.seekTo(offset, from);
        }
    }
}

import std.typecons : RefCounted, RefCountedAutoInitialize;
alias FixedBuffer(Stream) = RefCounted!(FixedBufferBase!(Stream), RefCountedAutoInitialize.no);
