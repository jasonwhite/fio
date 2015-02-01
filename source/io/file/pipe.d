/**
 * Copyright: Copyright Jason White, 2015
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.file.pipe;

import io.file.stream;

struct Pipe
{
    File readEnd;  // Read end
    File writeEnd; // Write end

    /**
     * Forwards reads and writes to the appropriate ends of the pipe.
     */
    size_t read(void[] buf)
    {
        return readEnd.read(buf);
    }

    /// Ditto
    size_t write(const(void)[] buf)
    {
        return writeEnd.write(buf);
    }
}

/**
 * Creates an unnamed, unidirectional pipe that can be written to on one end and
 * read from on the other.
 */
Pipe pipe(F = File)()
    if (is(F == class))
{
    version (Posix)
    {
        import core.sys.posix.unistd : pipe;

        int fd[2] = void;
        sysEnforce(pipe(fd) != -1);
        return Pipe(new F(fd[0]), new F(fd[1]));
    }
    else version(Windows)
    {
        import core.sys.windows.windows : CreatePipe;

        Handle readEnd, writeEnd;
        sysEnforce(CreatePipe(&readEnd, &writeEnd, null, 0));
        return Pipe(new File(readEnd), new File(writeEnd));
    }
    else
    {
        static assert(false, "Unsupported platform.");
    }
}

///
unittest
{
    auto p = pipe();

    // Write to one end of the pipe...
    immutable message = "Indubitably.";
    p.write(message);

    // ...and read from it on the other.
    char[message.length] buf;
    assert(buf[0 .. p.read(buf)] == message);
}
