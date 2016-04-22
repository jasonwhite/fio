/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.file.pipe;

import io.file.stream;

struct Pipe(F = File)
    if (is(F == struct))
{
    F readEnd;  // Read end
    F writeEnd; // Write end
}

/**
 * Creates an unnamed, unidirectional pipe that can be written to on one end and
 * read from on the other.
 */
Pipe!F pipe(F = File)()
    if (is(F == struct))
{
    version (Posix)
    {
        import core.sys.posix.unistd : pipe;

        int[2] fd = void;
        sysEnforce(pipe(fd) != -1);
        return Pipe!F(F(fd[0]), F(fd[1]));
    }
    else version(Windows)
    {
        import core.sys.windows.windows : CreatePipe;

        F.Handle readEnd = void, writeEnd = void;
        sysEnforce(CreatePipe(&readEnd, &writeEnd, null, 0));
        return Pipe!F(F(readEnd), F(writeEnd));
    }
    else
    {
        static assert(false, "Unsupported platform.");
    }
}

///
unittest
{
    import core.thread : Thread;

    immutable message = "The quick brown fox jumps over the lazy dog.";

    auto p = pipe();

    void writer()
    {
        p.writeEnd.write(message);

        // Since this is buffered, it must be flushed in order to avoid a
        // deadlock.
        p.writeEnd.flush();
    }

    auto thread = new Thread(&writer).start();

    // Read the message from the other thread.
    char[message.length] buf;
    assert(buf[0 .. p.readEnd.read(buf)] == message);

    thread.join();
}
