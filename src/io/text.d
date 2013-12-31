/**
  Copyright: Copyright Jason White, 2013-
  License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
  Authors:   Jason White
 */
module io.text;

import io.stream;


/**
  Wraps a stream such that reads and writes are deferred for as long as
  possible.
 */
struct TextStream(S)
    if (isSource!S || isSink!S)
{
    private S _stream;
    alias _stream this;

    @disable this(this);

    // Call super class constructors.
    this(Args...)(auto ref Args args)
        if(is(typeof(S(args))))
    {
        _stream = S(args);
    }

    static if (isSource!S)
    {
        size_t readf(Char, T...)(in Char[] fmt, T args)
        {
            // TODO
            return 0;
        }

        size_t readln(Char)(ref Char[] buf, dchar terminator = '\n')
        {
            // TODO
            return 0;
        }

        /**
          Returns a range that iterates over the lines in a stream.
         */
        version (none)
        @property auto byDelimiter(Terminator = char, Char = char)
            (bool keepTerm = false, Terminator t = '\n')
        {
            struct ByDelimiter
            {
                bool empty()
                {
                    return true;
                }

                const(Char[]) front()
                {
                    return null;
                }

                void popFront()
                {
                }
            }

            return ByDelimiter();
        }
    }

    static if (isSink!S)
    {
        size_t write(T...)(T args)
        {
            // TODO
            return 0;
        }

        size_t writeln(T...)(T args)
        {
            // TODO
            return 0;
        }

        size_t writef(Char, T...)(in Char[] fmt, T args)
        {
            // TODO
            return 0;
        }

        size_t writefln(Char, T...)(in Char[] fmt, T args)
        {
            // TODO
            return 0;
        }
    }
}
