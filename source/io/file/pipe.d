/**
 * Copyright: Copyright Jason White, 2014
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.file.pipe;

import io.file.file;

struct Pipe
{
    File readEnd;  // Read end
    File writeEnd; // Write end
}

/**
 * Creates an unnamed unidirectional pipe that can be written to on one end
 * and read from on the other. A bidirectional pipe can be created with two
 * unidirectional pipes.
 */
Pipe pipe()
{
    version (Posix)
    {
        import core.sys.posix.unistd : pipe;

        int fd[2];
        sysEnforce(pipe(fd) != -1);
        return Pipe(File(fd[0]), File(fd[1]));
    }
    else version(Windows)
    {
        import core.sys.windows.windows : CreatePipe;

        Handle readEnd, writeEnd;
        sysEnforce(CreatePipe(&readEnd, &writeEnd, null, 0));
        return Pipe(File(readEnd), File(writeEnd));
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
    p.writeEnd.write(message);

    // ...and read from it on the other.
    char[message.length] buf;
    assert(buf[0 .. p.readEnd.read(buf)] == message);
}
