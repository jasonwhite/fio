/**
 * Copyright: Copyright Jason White, 2013-
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.stdio;

version (none):

public import io.stream,
              io.file,
              io.locking,
              io.buffered,
              io.text;

// TODO: Make this RefCounted too?
alias File = TextStream!(BufferedStream!(LockingStream!FileStream));

/**
 * Standard I/O streams.
 *
 * NOTE: An exception will be thrown on destruction because std.stdio also closes
 * these file handles. This will not be a problem if std.stdio is replaced by
 * this module.
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
        stdin  = File(0);
        stdout = File(1);
        stderr = File(2);
    }
}

/**
 * These functions are the same as the ones provided by $(D io.text.TextStream),
 * but they act on $(D stdin) and $(D stdout).
 */
size_t readf(Char, T...)(in Char[] fmt, T args)
{
    return stdin.readf(fmt, args);
}

/// Ditto
size_t readln(Char)(ref Char[] buf, dchar terminator = '\n')
{
    return stdin.readln(buf, terminator);
}

/// Ditto
size_t write(T...)(T args)
{
    return stdout.write(args);
}

/// Ditto
size_t writeln(T...)(T args)
{
    return stdout.writeln(args);
}

/// Ditto
size_t writef(Char, T...)(in Char[] fmt, T args)
{
    return stdout.writef(fmt, args);
}

/// Ditto
size_t writefln(Char, T...)(in Char[] fmt, T args)
{
    return stdout.writefln(fmt, args);
}
