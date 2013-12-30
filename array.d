/**
  Copyright: Copyright Jason White, 2013-
  License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
  Authors:   Jason White
 */
module io.array;

import std.algorithm;

import io.stream;

/**
  A stream that works on an array.

  Note that there is little point in buffering this type of stream.
 */
struct ArrayStream
{
    private
    {
        // Memory block data.
        ubyte[] data;

        // The current position in the memory block.
        size_t pos;

        // Number of elements to grow the buffer by.
        size_t _alignment = 1024;
    }

    @disable this(this);

    /**
      The number of elements to grow the buffer by.
     */
    @property void alignment(size_t n) { _alignment = n; }
    @property size_t alignment() { return _alignment; } /// Ditto

    const(ubyte)[] peekData(size_t n)
    {
        return data[pos .. pos + min(data.length - pos, n)];
    }

    ubyte[] peekData(ubyte[] buf)
    {
        // Copy it
        auto data = peekData(buf.length);
        return buf[0 .. data.length] = data;
    }

    /**
      Reads a specified number of elements from the stream and returns a slice
      of the data.
     */
    const(ubyte)[] readData(size_t n)
    {
        auto data = peekData(n);
        pos += data.length;
        return data;
    }

    /**
      Copies the data to a buffer.
     */
    const(ubyte)[] readData(ubyte[] buf)
    {
        // Copy it
        auto data = readData(buf.length);
        return buf[0 .. data.length] = data;
    }

    /**
      Writes the data to the stream. The internal memory buffer is grown if
      necessary.
     */
    size_t writeData(in ubyte[] buf)
    {
        if (pos + buf.length > data.length)
            data.length += buf.length;

        buf.copy(data[pos .. $]);
        pos += buf.length;
        return buf.length;
    }

    ulong seek(long offset, From from = From.start)
    {
        ulong pos = void;

        final switch (from)
        {
        case From.start:
            pos = offset;
            break;
        case From.end:
            pos = data.length - offset;
            break;
        case From.here:
            pos += offset;
            break;
        }

        if (pos > data.length)
            throw new SeekException("Cannot seek past end.");

        this.pos = pos;
        return pos;
    }
}

unittest
{
    auto s = ArrayStream();

    // Empty read
    assert(s.peekData(10) == []);
    assert(s.readData(10) == []);

    // Test basic read/write.
    assert(s.writeData([1, 2, 3, 4]) == 4);
    s.seek(0);
    assert(s.peekData(4) == [1, 2, 3, 4]);
    assert(s.readData(4) == [1, 2, 3, 4]);

    // Test overwriting
    s.seek(0);
    assert(s.writeData([4, 3, 2, 1]) == 4);
    s.seek(0);
    assert(s.readData(4) == [4, 3, 2, 1]);

    // Test multiple writes and reads
    s.seek(0);
    assert(s.writeData([1, 2, 3, 4]) == 4);
    assert(s.writeData([5, 6, 7, 8, 9, 10]) == 6);
    s.seek(0);
    assert(s.readData(10) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    s.seek(4);
    assert(s.readData(4) == [5, 6, 7, 8]);
    assert(s.readData(4) == [9, 10]);

    // Test reading into a buffer.
    s.seek(0);
    ubyte[] buf;
    buf.length = 16;
    assert(s.readData(buf) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
}
