/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.stream.types;

/**
 * Specifies how to access a stream.
 */
enum Access
{
    /// Default access. Not very useful.
    none = 0,

    /// Allows only read operations on the stream.
    read = 1 << 0,

    /// Allows only write operations on the stream.
    write = 1 << 1,

    /// Allows data to be executed. This is only used for memory mapped files.
    execute = 1 << 2,

    /// Allows both read and write operations on the stream.
    readWrite = read | write,

    /// Complete access.
    all = read | write | execute,
}

/**
 * Relative position to seek from.
 */
enum From
{
    /// Seek relative to the beginning of the stream.
    start,

    /// Seek relative to the current position in the stream.
    here,

    /// Seek relative to the end of the stream.
    end,
}

/**
 * Stream exceptions.
 */
class StreamException : Exception       { this(string msg) { super(msg); } }

/// Ditto
class ReadException   : StreamException { this(string msg) { super(msg); } }

/// Ditto
class WriteException  : StreamException { this(string msg) { super(msg); } }

/// Ditto
class SeekException   : StreamException { this(string msg) { super(msg); } }
