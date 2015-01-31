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

/**
 * Standard I/O streams.
 *
 * Note: To avoid conflict with other libraries accessing these standard
 * streams, their file handle is duplicated and closed upon static destruction.
 */
__gshared
{
    /// Standard input stream.
    File stdin;

    /// Standard output stream.
    File stdout;

    /// Standard error stream.
    File stderr;
}

shared static this()
{
    // Initialize stdio streams.
    version (Posix)
    {
        import core.sys.posix.unistd : dup;
        stdin  = new File(dup(0));
        stdout = new File(dup(1));
        stderr = new File(dup(2));
    }
    else version (Windows)
    {
        static assert(false, "Implement me.");
    }
}
