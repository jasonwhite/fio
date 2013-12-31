/**
  Copyright: Copyright Jason White, 2013-
  License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
  Authors:   Jason White
 */
module io.stream;

/**
  Checks if a type is a source. A source is a stream that can be read from and
  must define the member function $(D readData).
 */
enum isSource(S) =
    is(typeof({
        S s = void;
        ubyte[] buf;
        ubyte[] d = s.readData(buf);
    }));

unittest
{
    static struct A {}
    static assert(!isSource!A);

    static struct B {
        ubyte[] readData(ubyte[] buf) { return buf; }
    }
    static assert(isSource!B);

    static struct C {
        void readData() {}
    }
    static assert(!isSource!C);

    static struct D {
        char[] readData(char[] buf) { return buf; }
    }
    static assert(!isSource!D);
}

/**
  Checks if a type is a sink. A sink is a stream that can be written to and must
  define the member function $(D writeData).
 */
enum isSink(S) =
    is(typeof({
        S s = void;
        size_t n = s.writeData(cast(ubyte[])[1, 2, 3]);
    }));

unittest
{
    static struct A {}
    static assert(!isSink!A);

    static struct B {
        size_t writeData(in ubyte[] data) { return 0; }
    }
    static assert(isSink!B);

    static struct C {
        void writeData() {}
    }
    static assert(!isSink!C);

    static struct D {
        size_t writeData(in D[] buf) { return 0; }
    }
    static assert(!isSink!D);
}

/**
  Checks if a type is seekable.
 */
enum isSeekable(S) =
    is(typeof({
        S s = void;
        ulong pos = s.seek(cast(long)42, From.start);
    }));

unittest
{
    static struct A {}
    static assert(!isSeekable!A);

    static struct B {
        ulong seek(ulong pos, From from) { return 0; }
    }
    static assert(isSeekable!B);
}

/**
  Seek position origin.
 */
enum From
{
    start, /// Relative to the beginning.
    here,  /// Relative to the current position.
    end,   /// Relative to the end.
}

/**
  Stream exceptions.
 */
class StreamException : Exception       { this(string msg) { super(msg); } }

/// Ditto
class ReadException   : StreamException { this(string msg) { super(msg); } }

/// Ditto
class WriteException  : StreamException { this(string msg) { super(msg); } }

/// Ditto
class SeekException   : StreamException { this(string msg) { super(msg); } }

/**
  A stream implementation of /dev/null.

  A stream that does nearly nothing. Reads return zero's and writes get sucked
  into a black hole.

  This stream serves two purposes: to act as a reference and to be used in unit
  tests.
 */
struct NullStream
{
    /**
      Fills the buffer with zeros.
     */
    ubyte[] readData(ubyte[] buf)
    {
        foreach (ref e; buf)
            e = e.init;

        return buf;
    }

    /**
      Simply returns the length of the data array.
     */
    size_t writeData(in ubyte[] data)
    {
        return data.length;
    }

    /**
      Seeking is meaningless when all data is the same.
     */
    ulong seek(long offset, From from = From.start)
    {
        return 0;
    }
}

unittest
{
    auto s = NullStream();

    // reading
    auto buf = new ubyte[16];
    buf[4] = buf[10] = 42; // Random samples to be overwritten
    assert(s.readData(buf) == buf);
    assert(buf[4] == 0 && buf[10] == 0);

    // writing
    assert(s.writeData([1, 2, 3, 4]) == 4);
}

/**
  Returns a range that iterates over a stream a chunk of bytes at a time.
  Buffering will be taken advantage of if it is available in the stream.
 */
version (none)
auto byChunk(Source stream, size_t size)
{
    static struct ByChunk(S stream)
    {
        private
        {
            S _stream;
            size_t _size;

            // TODO: Check if stream is buffered?
            ubyte[] _chunk;
        }

        this(S stream, size_t size)
        in
        {
            assert(size > 0);
        }
        body
        {
            _stream = stream;
            _size = size;
        }

        /**
          Returns true if the end of the stream has been reached.
         */
        bool empty()
        {
            // TODO
            return true;
        }

        /**
          Returns the current chunk. The returned slice is only valid until the
          next call to $(D popFront).
         */
        ubyte[] front()
        {
            // TODO
            return [];
        }

        /**
          Advances to the next chunk.
         */
        void popFront()
        {
            // TODO
        }
    }

    return ByChunk!S(stream, size);
}

/**
  Returns a range that iterates over a type T in a stream.
 */
version (none)
@property auto byRecord(T, Stream)(Stream s)
    if (isSource!Stream)
{
    struct ByRecord
    {
    }

    return ByRecord();
}

/**
  Copy the entirety of $(D source) to $(D sink). If $(D sink) could not take
  everything from $(D source), an exception is thrown.
 */
size_t copy(Source, Sink)(Source source, Sink sink, ubyte[] buf)
    if (isSource!Source && isSink!Sink)
{
    size_t len;

    while (true)
    {
        auto read = source.readData(buf);
        if (read.length != buf.length) break;
        sink.writeExactly(read);
        len += read.length;
    }

    return len;
}

/// Ditto
size_t copy(Source, Sink)(Source source, Sink sink)
    if (isSource!Source && isSink!Sink)
{
    ubyte[1024] buf;
    return copy(source, sink, buf);
}

/**
  Copies the first n bytes of the stream $(D source) to the stream $(D sink).
  If the sink stream could not take everything from the source stream, an
  exception is thrown.
 */
void copy(Source, Sink)(Source source, Sink sink, size_t n, ubyte[] buf)
    if (isSource!Source && isSink!Sink)
{
    while (n > 0)
    {
        n -= sink.writeExactly(
            source.readExactly(buf[0 .. (n < buf.length ? n : $)])
            );
    }
}

/// Ditto
void copy(Source, Sink)(Source source, Sink sink, size_t n)
    if (isSource!Source && isSink!Sink)
{
    ubyte[1024] buf;
    copy(source, sink, n, buf);
}
