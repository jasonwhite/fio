/**
  Copyright: Copyright Jason White, 2013-
  License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
  Authors:   Jason White
 */
module io.buffered;

import io.stream;

/**
  Checks if a type is a buffered source.
 */
enum isBufferedSource(S) = isSource!S &&
    is(typeof({
        S s = void;
        ubyte[] data;
        data = s.readData(4);
        data = s.peekData(4);
        data = s.peekData(data);
    }));

/**
  Checks if a type is a buffered sink.
 */
enum isBufferedSink(S) = isSink!S &&
    is(typeof({
        S s = void;
        s.flush();
    }));

// Aligns a number $(D n) such that the result is >= $(D n) and is a multiple of
// $(D alignment).
private size_t alignTo(size_t n, size_t alignment) pure nothrow
{
    return alignment * ((n-1)/alignment + 1);
}

unittest
{
    static assert(alignTo(7,   1)   == 7);
    static assert(alignTo(0,   128) == 0);
    static assert(alignTo(1,   128) == 128);
    static assert(alignTo(128, 128) == 128);
    static assert(alignTo(129, 128) == 256);
}

/**
  Wraps a stream such that reads and writes are grouped into larger chunks to
  avoid interacting with the underlying stream.

  Buffering is most useful for streams that have slow response times (such as
  disks). In cases where making many individual reads or writes will incur a
  significant drop in performance, a buffer should be used.
 */
struct BufferedStream(S)
    if (isSource!S || isSink!S)
{
    static if (isSource!S && isSink!S)
    {
        // Buffered streams require seek if the base stream is both readable and
        // writable.
        static assert(isSeekable!S, S.stringof ~ " must be seekable.");
    }

    private
    {
        // Base stream
        S _stream;

        // Buffered data. This buffer will grow and shrink as necessary.
        ubyte[] _buffer;

        // Valid slice into the buffer.
        ubyte[] _valid;

        // Number of bytes to align the buffer to.
        size_t _alignment = 4096;
    }

    alias _stream this;

    @disable this(this);

    // Mimic base stream constructor.
    this(Args...)(auto ref Args args)
        if (is(typeof(S(args))))
    {
        _stream = S(args);
    }

    ~this()
    {
        static if (isSink!S)
        {
            flush();
        }
    }

    /**
      The number of bytes to align the buffer to.
     */
    @property void alignment(size_t n) { _alignment = n; }
    @property size_t alignment() { return _alignment; } /// Ditto

    static if (isSource!S)
    {
        /**
          Reads up to the number of specified bytes without consuming them. A
          slice to the data is returned. The data in the slice is guaranteed
          to be valid only until the next read or write operation.
         */
        const(ubyte)[] peekData(size_t n)
        {
            if (n > _valid.length)
            {
                // Not all of the data is in the buffer, get it from the stream.

                import std.algorithm : copy;

                // Copy remaining valid data to the beginning of the buffer.
                // Note that these two arrays may overlap.
                if (_valid.length > 0)
                    _valid.copy(_buffer);

                // Reserve enough space for the data
                _buffer.length = n.alignTo(_alignment);

                // Fill the rest of the buffer.
                _valid = _stream.readData(_buffer[_valid.length .. $]);
            }

            return _valid[0 .. n];
        }

        /**
          Reads data without consuming it.

          This is like $(D peekData(size_t n)), but copies the data to a buffer.
         */
        ubyte[] peekData(ubyte[] buf)
        {
            // FIXME: Avoid double buffering on large reads

            // Copy it
            auto data = peekData(buf.length);
            return buf[0 .. data.length] = data;
        }

        /**
          Reads a specified amount of data from the stream. A slice to the
          internal buffer is returned.

          Note that the data in the returned slice is only valid until the next
          call to $(D readData). If the data is needed beyond that point, copy
          it.

          This function can be more efficient than $(D readData(ubyte[] buf))
          because it avoids copying data from the internal buffer.
         */
        const(ubyte)[] readData(size_t n)
        {
            auto data = peekData(n);
            _valid = cast(ubyte[])data[n .. $];
            return data;
        }

        /**
          Reads data from the buffer or from the underlying stream if the buffer
          does not have the required data.
         */
        ubyte[] readData(ubyte[] buf)
        {
            // TODO: Avoid double buffering on large reads.

            // Copy it
            auto data = readData(buf.length);
            return buf[0 .. data.length] = data;
        }
    }

    static if (isSink!S)
    {
        /**
          Writes any buffered data to the underlying stream.

          The stream is automatically flushed either upon transitioning from
          writing to reading or when the buffer gets too full.
         */
        void flush()
        {
            // TODO
            //_stream.writeData();
        }

        /**
          Writes data to the buffer or to the underlying stream if the buffer is
          full.
         */
        size_t writeData(in ubyte[] data)
        {
            // Fill up the toilet until it's too big to go down.
            if (_valid.length)
            {
            }

            return 0;
        }
    }

    static if (isSeekable!S)
    {
        ulong seek(long offset, From from = From.start)
        {
            // TODO
            return _stream.seek(offset, from);
        }
    }
}

unittest
{
    // Buffered streams should give the same results as unbuffered streams.

    auto s = BufferedStream!NullStream();

    assert(s.readData(4) == [0, 0, 0, 0]);
}
