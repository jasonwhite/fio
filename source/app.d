version (unittest)
{
    void main()
    {
    }
}
else
{
    import io.file.stream, io.file.mmap, io.file.temp;
    import std.datetime, std.random;
    import std.parallelism;
    import stdio = std.stdio;

    // Creates a 1 GiB file containing random data.
    // Takes ~2 seconds on my machine.
    void main()
    {
        auto sw = StopWatch(AutoStart.yes);

        auto f = tempFile();
        f.length = 1024^^3; // 1 GiB

        auto map = f.memoryMap(Access.readWrite);
        auto data = cast(size_t[])map;

        foreach (i, ref e; parallel(data))
            e = uniform!"[]"(size_t.min, size_t.max);

        stdio.writeln("Time Taken: ", cast(Duration)sw.peek);
    }
}
