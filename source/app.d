version (unittest)
    void main() {}
else:

import io.file, io.mmfile;
import std.datetime, std.random;
import std.parallelism;
import stdio = std.stdio;

// Creates a 1 GiB file containing random data.
// Takes ~3 seconds on my machine.
void main()
{
    auto sw = StopWatch(AutoStart.yes);

    auto f = File("/tmp/large_file", FileFlags.readWriteEmpty);
    f.length = 1024^^3;

    auto map = f.MmFile(Access.readWrite);
    auto data = cast(ulong[])map;

    foreach (i, ref e; parallel(data))
        e = uniform!"[]"(ulong.min, ulong.max);

    stdio.writeln("Time Taken: ", cast(Duration)sw.peek);
}
