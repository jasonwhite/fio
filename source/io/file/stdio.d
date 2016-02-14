/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 *
 * Description:
 * Provides access to the standard I/O streams: $(D stdin), $(D stdout), and $(D
 * stderr). Note that each of these streams are buffered.
 *
 * To avoid conflict with $(D std._stdio), the file handles of each stream are
 * duplicated on static construction and closed upon static destruction.
 */
module io.file.stdio;

import io.file.stream;
import io.buffer.fixed;

__gshared
{
    /**
     * Standard input stream.
     *
     * Example:
     * Counting the number of lines from standard input.
     * ---
     * import io;
     * size_t lines = 0;
     * foreach (line; stdin.byLine)
     *     ++lines;
     * ---
     */
    File stdin;

    /**
     * Standard output stream.
     *
     * Example:
     * ---
     * import io;
     * stdout.write("Hello world!\n");
     * stdout.flush();
     * ---
     */
    File stdout;

    /**
     * Standard error stream.
     *
     * stderr is often used for writing error messages or printing status
     * updates.
     *
     * Example:
     * Prints a useful status message.
     * ---
     * import core.thread : Thread;
     * import core.time : dur;
     *
     * immutable status = ".oO*";
     *
     * for (size_t i = 0; ; ++i)
     * {
     *     Thread.sleep(dur!"msecs"(100));
     *     stderr.write("Reticulating splines... ");
     *     stderr.write([status[i % status.length], '\r']);
     *     stderr.flush();
     * }
     * ---
     */
    File stderr;
}

shared static this()
{
    // Initialize stdio streams.
    version (Posix)
    {
        import core.sys.posix.unistd : dup;
        stdin  = File.dup(0);
        stdout = File.dup(1);
        stderr = File.dup(2);
    }
    else version (Windows)
    {
        import core.sys.windows.windows;
        stdin  = File.dup(GetStdHandle(STD_INPUT_HANDLE));
        stdout = File.dup(GetStdHandle(STD_OUTPUT_HANDLE));
        stderr = File.dup(GetStdHandle(STD_ERROR_HANDLE));
    }
}

shared static ~this()
{
    stderr.flush();
    stdout.flush();
}
