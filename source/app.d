version (unittest)
{
    void main()
    {
    }
}
else
{
    import io;
    import std.datetime, std.random;
    import std.parallelism;

    // Creates a 1 GiB file containing random data.
    // Takes ~2 seconds on my machine.
    void main()
    {
        auto sw = StopWatch(AutoStart.yes);

        auto f = tempFile();
        f.length = 1024^^3; // 1 GiB

        auto map = f.memoryMap!size_t(Access.write);

        foreach (i, ref e; parallel(map[]))
            e = uniform!"[]"(size_t.min, size_t.max);

        println("Time Taken: ", cast(Duration)sw.peek);
    }
}
