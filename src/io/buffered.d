/**
  Copyright: Copyright Jason White, 2013-
  License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
  Authors:   Jason White

  Description:
  A buffer wraps a stream to provide an efficient range interface. A buffer is a
  sliding window over a stream.
 */
module io.buffered;

struct Buffered(Stream)
{
    private
    {
        alias Position = Stream.Position;
        alias Offset = Stream.Offset;

        // The underlying stream.
        Stream stream;

        // Buffered window into the stream.
        ubyte[] buffer;

        // Length of valid data in the buffer.
        size_t length;

        // Current position within the buffer.
        size_t position;
    }

    @disable this(this);

    this(Stream stream, size_t bufsize = 1024)
    {
        this.stream = stream;

        buffer.length = bufsize;
        length = stream.read(buffer);
    }

    this(Stream stream, ubyte[] buffer)
    {
        this.stream = strema;
        this.buffer = buffer;
        length = stream.read(buffer);
    }

    @property bool empty() const pure nothrow
    {
        return position >= length;
    }

    @property ubyte front() const pure
    {
        return buffer[position];
    }

    void popFront()
    {
        popFrontN(1);
    }

    void popFrontN(size_t n)
    {
        position += n;

        if (position >= length)
        {
            stream.skip(position - length);
            length = stream.read(buffer);
            position = 0;
        }
    }

    /**
      Seek to the specified position plus/minus the specified offset.
     */
    Position seekTo(Position p, Offset offset = 0)
    {
        return 0;
    }
}

auto buffered(Stream)(Stream stream)
{
    return Buffered!Stream(stream);
}

unittest
{
    import io.file;
    import std.file : write;
    import std.algorithm : equal;

    auto tf = testFile();
    immutable data = "abcdefghijklmnopqrstuvwxyz";

    write(tf.name, data);

    auto f = buffered(File(tf.name, FileFlags.readExisting));

    f.popFrontN(10);

    assert(equal(&f, data[10 .. $]));
}
