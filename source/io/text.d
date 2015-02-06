/**
 * Copyright: Copyright Jason White, 2015
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 *
 * TODO: Find a more elegant way of reading and writing text.
 */
module io.text;

import io.stream;

/**
 * Serializes the given arguments to a text representation followed by a new
 * line.
 */
size_t print(T...)(Sink sink, auto ref T args)
{
    import std.conv : to;

    size_t length;

    foreach (arg; args)
        length += sink.write(arg.to!string);

    return length;
}

/// Ditto
size_t print(T...)(shared(Sink) sink, auto ref T args)
{
    import std.algorithm : forward;
    synchronized (sink)
        return (cast(Sink)sink).print(forward!args);
}

/// Ditto
size_t print(T...)(auto ref T args)
    if (T.length > 0 && !is(T[0] : Sink) && !is(T[0] : shared(Sink)))
{
    import io.file.stdio : stdout;
    import std.algorithm : forward;
    return stdout.print(forward!args);
}

unittest
{
    import io.file.pipe;
    import std.typecons : tuple;
    import std.typetuple : TypeTuple;

    // First tuple value is expected output. Remaining are the types to be
    // printed.
    alias tests = TypeTuple!(
        tuple(""),
        tuple("Test", "Test"),
        tuple("[4, 8, 15, 16, 23, 42]", [4, 8, 15, 16, 23, 42]),
        tuple("The answer is 42", "The answer is ", 42),
        tuple("01234567890", 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0),
        );

    foreach (t; tests)
    {
        auto f = pipe();
        immutable output = t[0];
        char[output.length] buf;
        assert(f.writeEnd.print(t[1 .. $]) == output.length);
        assert(f.readEnd.read(buf) == buf.length);
        assert(buf == output);
    }
}

/**
 * Serializes the given arguments to a text representation followed by a new
 * line.
 */
size_t println(T...)(Sink sink, auto ref T args)
{
    import std.conv : to;

    size_t length;

    foreach (arg; args)
        length += sink.write(arg.to!string);

    length += sink.write("\n");

    return length;
}

/// Ditto
size_t println(T...)(shared(Sink) sink, auto ref T args)
{
    import std.algorithm : forward;
    synchronized (sink)
        return (cast(Sink)sink).println(forward!args);
}

/// Ditto
size_t println(T...)(auto ref T args)
    if (T.length > 0 && !is(T[0] : Sink) && !is(T[0] : shared(Sink)))
{
    import io.file.stdio : stdout;
    import std.algorithm : forward;
    return stdout.println(forward!args);
}

unittest
{
    import io.file.pipe;
    import std.typecons : tuple;
    import std.typetuple : TypeTuple;

    // First tuple value is expected output. Remaining are the types to be
    // printed.
    alias tests = TypeTuple!(
        tuple("\n"),
        tuple("Test\n", "Test"),
        tuple("[4, 8, 15, 16, 23, 42]\n", [4, 8, 15, 16, 23, 42]),
        tuple("The answer is 42\n", "The answer is ", 42),
        tuple("01234567890\n", 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0),
        );

    foreach (t; tests)
    {
        auto f = pipe();
        immutable output = t[0];
        char[output.length] buf;
        assert(f.writeEnd.println(t[1 .. $]) == output.length);
        assert(f.readEnd.read(buf) == buf.length);
        assert(buf == output);
    }
}

/**
 * Serializes the given arguments according to the given format specifier
 * string.
 */
@property size_t printf(T...)(Sink sink, string format, auto ref T args)
{
    // TODO
    return 0;
}

/// Ditto
size_t printf(T...)(shared(Sink) sink, string format, auto ref T args)
{
    import std.algorithm : forward;
    synchronized (sink)
        return (cast(Sink)sink).printf(format, forward!args);
}

/// Ditto
@property size_t printf(T...)(string format, auto ref T args)
    if (T.length > 0 && !is(T[0] : Sink) && !is(T[0] : shared(Sink)))
{
    import io.file.stdio : stdout;
    import std.algorithm : forward;
    return stdout.printf(forward!(format, args));
}

/**
 * Like $(D writef), but also writes a new line.
 */
@property size_t printfln(T...)(Sink sink, string format, auto ref T args)
{
    // TODO
    return 0;
}

/// Ditto
size_t printfln(T...)(shared(Sink) sink, string format, auto ref T args)
{
    import std.algorithm : forward;
    synchronized (sink)
        return (cast(Sink)sink).printfln(format, forward!args);
}

/// Ditto
@property size_t printfln(T...)(string format, auto ref T args)
    if (T.length > 0 && !is(T[0] : Sink) && !is(T[0] : shared(Sink)))
{
    import io.file.stdio : stdout;
    import std.algorithm : forward;
    return stdout.printfln(forward!(format, args));
}

/*
 * Checks if the given delimiter is a valid delimiter for an element of type T.
 */
template isValidDelimiter(Delimiter, T)
{
    import std.traits : isScalarType, isArray, Unqual;
    import std.range : ElementEncodingType;

    static if (isScalarType!Delimiter)
    {
        enum isValidDelimiter = true;
    }
    else static if (isArray!Delimiter)
    {
        static if (is(Unqual!(ElementEncodingType!Delimiter) == T))
            enum isValidDelimiter = true;
        else
            enum isValidDelimiter = false;
    }
    else
        enum isValidDelimiter = false;
}

unittest
{
    static assert( isValidDelimiter!(char, char));
    static assert( isValidDelimiter!(string, char));
    static assert( isValidDelimiter!(dstring, dchar));
    static assert(!isValidDelimiter!(dstring, wchar));
    static assert(!isValidDelimiter!(dstring, char));
    static assert(!isValidDelimiter!(wstring, char));
    static assert( isValidDelimiter!(dchar, char));
    static assert( isValidDelimiter!(int, char));
    static assert( isValidDelimiter!(short, int));
}

struct ByLine(T, Delimiter)
    if (isValidDelimiter!(Delimiter, T))
{
    private
    {
        import std.array : Appender;
        import io.block : Block, byBlock;

        // Holds the current line
        Appender!(T[]) _line;

        // Iterates over the stream in small blocks
        Block!(T, Source) _blocks;

        // Are we there yet?
        bool _empty = false;

        // Character or sequence of characters that terminates a line.
        immutable Delimiter _delimiter;
    }

    @disable this(this);

    this(Source source, Delimiter delimiter)
    {
        _blocks = source.byBlock!T;
        _delimiter = delimiter;

        // Prime the cannons
        popFront();
    }

    /*
     * Finds the length of the delimiter relative to the size of a single
     * element in the line.
     */
    private @property size_t delimiterLength() const pure nothrow
    {
        import std.traits : isScalarType, isArray;

        static if (isScalarType!Delimiter)
        {
            return 1;
        }
        else static if (isArray!Delimiter)
        {
            return _delimiter.length;
        }
        else
        {
            static assert("Unable to find length of line delimiter");
        }
    }

    /**
     * Reads the next line.
     */
    void popFront()
    {
        import std.algorithm : endsWith;

        version(assert)
        {
            import core.exception : RangeError;
            if (empty) throw new RangeError();
        }

        _line.clear();

        if (_blocks.empty)
        {
            _empty = true;
            return;
        }

        foreach (immutable ch; _blocks)
        {
            _line.put(ch);

            if (_line.data.endsWith(_delimiter))
            {
                // Truncate the line to not include the delimiter
                // FIXME: Handle arrays and ranges of delimiters
                _line.shrinkTo(_line.data.length - delimiterLength);
                break;
            }
        }

        // popFront is not called when the loop exits, so we call it here.
        _blocks.popFront();
    }

    /**
     * Gets the current line in the stream.
     */
    const(T)[] front()
    {
        version(assert)
        {
            import core.exception : RangeError;
            if (empty) throw new RangeError();
        }

        return _line.data;
    }

    /**
     * Returns true if there are no more lines to read from the stream.
     */
    bool empty()
    {
        return _empty;
    }
}

/**
 * Convenience function for returning a line reader.
 */
@property auto byLine(T = char)
    (Source source)
{
    return ByLine!(T, char)(source, '\n');
}

/// Ditto
@property auto byLine(T = char, Delimiter = char)
    (Source source, Delimiter delimiter)
{
    return ByLine!(T, Delimiter)(source, delimiter);
}

version (unittest)
{
    void testByLine(const string[] lines, string delimiter)
    {
        import io.file.temp;
        import std.array : join;
        import std.algorithm : equal;

        immutable text = lines.join(delimiter);

        auto f = tempFile();
        f.writeExactly(text);
        f.position = 0;

        assert(f.byLine(delimiter).equal(lines));
        assert(f.position == text.length);

        // Add a trailing terminator at the end of the file.
        assert(f.write(delimiter) == delimiter.length);
        f.position = 0;
        assert(f.byLine(delimiter).equal(lines));
    }
}

unittest
{
    immutable lines = [
        "This is the first line",
        "",
        "That was a blank line.",
        "This is the penultimate line!",
        "This is the last line.",
    ];

    testByLine(lines, "\n");
    testByLine(lines, "\r\n");
}
