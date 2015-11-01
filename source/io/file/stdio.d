/**
 * Copyright: Copyright Jason White, 2015
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 *
 * Description:
 * Provides access to the standard I/O streams: stdin, stdout, and stderr.
 */
module io.file.stdio;

import io.file.stream;
import io.buffer.fixed;

/**
 * Standard I/O streams.
 *
 * Note: To avoid conflict with other libraries accessing these standard
 * streams, their file handle is duplicated and closed upon static destruction.
 */
__gshared
{
    /// Standard input stream.
    BufferedFile stdin;

    /// Standard output stream.
    BufferedFile stdout;

    /// Standard error stream.
    BufferedFile stderr;
}

shared static this()
{
    // Initialize stdio streams.
    version (Posix)
    {
        import core.sys.posix.unistd : dup;
        stdin  = BufferedFile.dup!BufferedFile(0);
        stdout = BufferedFile.dup!BufferedFile(1);
        stderr = BufferedFile.dup!BufferedFile(2);
    }
    else version (Windows)
    {
        import core.sys.windows.windows;
        stdin  = BufferedFile.dup!BufferedFile(GetStdHandle(STD_INPUT_HANDLE));
        stdout = BufferedFile.dup!BufferedFile(GetStdHandle(STD_OUTPUT_HANDLE));
        stderr = BufferedFile.dup!BufferedFile(GetStdHandle(STD_ERROR_HANDLE));
    }
}

shared static ~this()
{
    stderr.flush();
    stdout.flush();
}
