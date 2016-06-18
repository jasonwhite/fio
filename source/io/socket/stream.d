/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Thayne McCombs
 */
module io.socket.stream;

import io.stream;
import std.socket;

/**
 * A wrapper around a socket that provides stream functionality without buffering.
 */
struct UnbufferedSocketStreamBase
{
    /**
     * Create a new Stream from an existing Socket.
     *
     * Params:
     *   socket = The socket to make a stream from.
     *
     */
    this(Socket socket)
    {
        _socket = socket;
    }

    unittest
    {
        auto pair = socketPair();
        auto sock = UnbufferedSocketStream(pair[0]);
        assert(sock.isOpen);

        immutable ubyte[] data = [1,2,3,4,5];
        ubyte[10] buff;

        sock.write(data);

        assert(pair[1].receive(buff) == 5);
        assert(buff[0..5] == data);
    }

    /**
     * Create a new SocketStream that is connected to `address` as
     * a client. The socket is created in streaming mode (obviously).
     *
     * Params:
     *   address = The address to connect to.
     */
    this(Address address)
    {
        _socket = new Socket(address.addressFamily, SocketType.STREAM);
        _socket.connect(address);
    }

    unittest
    {
        auto server = new TcpSocket(AddressFamily.INET);
        server.bind(new InternetAddress("localhost", InternetAddress.PORT_ANY));
        server.listen(10);

        auto sock = SocketStream(server.localAddress);
        assert(sock.remoteAddress == server.localAddress);
        assert(sock.isOpen);
    }


    /**
     * Copying is disabled, because reference counting should be used instead.
     */
    @disable this(this);

    /**
     * Returns true if the socket is alive.
     */
    @property isOpen() @safe
    {
        return _socket && _socket.isAlive;
    }

    /**
     * Returns the underlying Socket.
     */
    @property socket() @safe
    {
        return _socket;
    }

    /**
     * Reads data from the socket.
     *
     * Params:
     *   buf = The buffer to read the data into. The length of the buffer
     *         specifies how much data should be read.
     *
     * Returns: The number of bytes that were read. If the socket is blocking
     *          wait for data to be available. If the remote side has closed
     *          the connection 0 is returned.
     *
     * Throws: SocketException on failure.
     */
    size_t read(scope ubyte[] buf) @safe
    in { assert(isOpen); }
    body
    {
        immutable n = _socket.receive(buf);
        socketEnforce(n != Socket.ERROR, "Failed to read from socket");
        return n;
    }

    unittest
    {
        auto pair = socketPair();
        auto sock = UnbufferedSocketStream(pair[0]);
        immutable ubyte[] data = [10,20,30,40];
        pair[1].send(data);
        ubyte[10] buff;
        assert(sock.read(buff) == 4);
        assert(buff[0..4] == data);
        pair[1].close();
        assert(sock.read(buff) == 0);
    }

    /**
     * Writes data to the socket.
     *
     * Params:
     *   data = The data to write to the file. The length of the slice indicates
     *          how much data should be written.
     *
     * Returns: The number of bytes that were written.
     *
     * Throws: SocketException on failure.
     */
    size_t write(in ubyte[] data) @safe
    in { assert(isOpen); }
    body
    {
        immutable n = _socket.send(data);
        socketEnforce(n != Socket.ERROR, "Failed to write to socket");
        return n;
    }

    unittest
    {
        auto pair = socketPair();
        auto sock = UnbufferedSocketStream(pair[0]);
        immutable ubyte[] data = [5,9,10];
        sock.write(data);
        ubyte[10] buff;
        assert(pair[1].receive(buff) == 3);
        assert(buff[0..3] == data);
        sock.write(data);
        sock.write(data);
        assert(pair[1].receive(buff) == 6);
        assert(buff[0..6] == data ~ data);
    }

    /// ditto
    alias put = write;

    /**
     * If the Socket is open, shut down both directions and close.
     * Otherwise, it does nothing.
     */
    void close() @safe
    {
        import std.socket : SocketShutdown;
        if (isOpen)
        {
            _socket.shutdown(SocketShutdown.BOTH);
            _socket.close();
        }
    }

    unittest
    {
        auto pair = socketPair();
        auto sock = UnbufferedSocketStream(pair[0]);
        sock.close();
        assert(!sock.isOpen);
        ubyte[1] buff;
        assert(pair[1].receive(buff) == 0);
    }

    /**
     * Detach the socket from this socket stream and return it.
     *
     * The stream is closed after becoming detached.
     * This can be used to avoid closing a socket when the stream is destroyed.
     */
    Socket detach() @safe
    {
        scope(success) { _socket = null; }
        return _socket;
    }

    /// Ditto
    ~this()
    {
        close();
    }

    alias _socket this;

private:
    Socket _socket;
}

unittest
{
    static assert(isSourceSink!UnbufferedSocketStreamBase);
}

/**
 * A stream that wraps a socket with buffered writes.
 */
struct SocketStreamBase {
    alias _stream this;

    @disable this(this);

    /**
     * Forwards argument to UnbufferedSocketStreamBase
     */
    this(T...)(auto ref T args)
    {
        import std.functional : forward;
        _stream = UnbufferedSocketStreamBase(forward!args);
        _buffer.length = 8192;
    }


    /**
     * Sets the size of the buffer. The default is 8192 bytes.
     * If there is currently data in the buffer, it will be flushed.
     */
    @property void bufferSize(size_t size)
    {
        if (_pos > 0)
        {
            flush();
        }
        _buffer.length = size;
    }

    /**
     * Get the current buffer size. The default is 8192 bytes (8KB).
     */
    @property size_t bufferSize() const pure nothrow @nogc
    {
        return _buffer.length;
    }

    /**
     * Upon destruction, any pending writes are flushed
     * to the socket.
     */
    ~this()
    {
        // don't use flush because we want to avoid throwing an error
        _stream.socket.send(_buffer[0.._pos]);
    }

    /**
     * Writes any pending data to the socket.
     */
    void flush() @safe
    {
        if (_pos > 0)
        {
            _stream.write(_buffer[0.._pos]);
            _pos = 0;
        }
    }

    /**
     * Write data to the stream, but buffer input
     * so that only sufficiently large packets are sent.
     */
    size_t write(in ubyte[] buf) @safe
    {
        immutable satisfied = writePartial(buf);
        if (satisfied == buf.length)
        {
            return satisfied;
        }

        const(ubyte)[] leftOver = buf[satisfied .. $];

        if (leftOver.length >= _buffer.length)
        {
            // leftOver is bigger than _buffer, write directly to socket
            return satisfied + _stream.write(leftOver);
        }
        else
        {
            return satisfied + writePartial(leftOver);
        }
    }

    unittest
    {
        auto pair = socketPair();
        auto sock = SocketStream(pair[0]);
        auto other = pair[1];
        other.blocking = false;
        sock.bufferSize = 10;

        ubyte[] data = [1,2,3,4,5];
        ubyte[20] buff;

        sock.write(data);
        assert(other.receive(buff) == Socket.ERROR);
        assert(wouldHaveBlocked());
        sock.write(data);
        assert(other.receive(buff) == 10);
        assert(buff[0..10] == data ~ data);
        sock.write(data);
        sock.flush();
        buff = 0;
        assert(other.receive(buff) == 5);
        assert(buff[0..5] == data);
    }

    private size_t writePartial(in ubyte[] buf) @safe
    {
        import std.algorithm : min;
        immutable satisfiable = min(_buffer.length - _pos, buf.length);
        _buffer[_pos .. _pos + satisfiable] = buf[0 .. satisfiable];
        _pos += satisfiable;

        if (_pos == _buffer.length)
        {
            // Buffer is full and there is more to write. Flush it.
            flush();
        }

        return satisfiable;
    }

    /**
     * Reads data from the socket.
     * The stream itself doesn't buffer reading
     * because the OS already buffers when receiving
     * on a streaming socket.
     */
    size_t read(scope ubyte[] buf) @safe
    {
        return _stream.read(buf);
    }


private:
    UnbufferedSocketStreamBase _stream;
    ubyte[] _buffer;
    size_t _pos;
}

unittest
{
    static assert(isSourceSink!SocketStreamBase);
}

import std.typecons : RefCounted, RefCountedAutoInitialize;
alias UnbufferedSocketStream = RefCounted!(StreamShim!UnbufferedSocketStreamBase, RefCountedAutoInitialize.no);
alias SocketStream = RefCounted!(StreamShim!SocketStreamBase, RefCountedAutoInitialize.no);

unittest
{
    static assert(isSourceSink!SocketStream);
    static assert(isSourceSink!UnbufferedSocketStream);
}


/**
 * Enforce that `check` is true, and throw a `SocketException` if it isn't.
 */
void socketEnforce(string file = __FILE__, size_t line = __LINE__)(bool check, lazy string msg = null)
{
    if (!check)
    {
        throw new SocketOSException(msg, file, line);
    }
}

/**
 * Call `accept` on the socket and return the result as a `SocketStream`.
 */
SocketStream acceptStream(Socket socket)
{
    return SocketStream(socket.accept());
}
