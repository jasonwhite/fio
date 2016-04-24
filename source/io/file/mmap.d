/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 *
 * Synopsis:
 * ---
 * // Creates a 1 GiB file containing random data.
 * import io.file;
 * import std.parallelism : parallel;
 * auto f = File("big_random_file.dat", FileFlags.writeNew);
 * f.length = 1024^^3; // 1 GiB
 *
 * auto map = f.memoryMap!size_t(Access.write);
 * foreach (i, ref e; parallel(map[]))
 *     e = uniform!"[]"(size_t.min, size_t.max);
 * ---
 */
module io.file.mmap;

public import io.file.stream;

version (Posix)
{
    import core.sys.posix.sys.mman;

    // Converts file access flags to POSIX protection flags.
    private @property int protectionFlags(Access access) pure nothrow
    {
        int flags = PROT_NONE;
        if (access & Access.read)    flags |= PROT_READ;
        if (access & Access.write)   flags |= PROT_WRITE;
        if (access & Access.execute) flags |= PROT_EXEC;
        return flags;
    }
}
else version (Windows)
{
    import core.sys.windows.windows;

    enum FILE_MAP_EXECUTE = 0x0020;

    // Converts file access flags to Windows protection flags.
    private @property DWORD protectionFlags(Access access) pure nothrow
    {
        switch (access)
        {
            case Access.read: return PAGE_READONLY;
            case Access.write: return PAGE_READWRITE;
            case Access.readWrite: return PAGE_READWRITE;
            case Access.read | Access.execute: return PAGE_EXECUTE_READ;
            case Access.write | Access.execute: return PAGE_EXECUTE_READWRITE;
            case Access.readWrite | Access.execute: return PAGE_EXECUTE_READWRITE;
            default: return PAGE_READONLY;
        }
    }

    // Converts file access flags to Windows MapViewOfFileEx flags
    private @property DWORD mapViewFlags(Access access) pure nothrow
    {
        DWORD flags = 0;
        if (access & Access.read)    flags |= FILE_MAP_READ;
        if (access & Access.write)   flags |= FILE_MAP_WRITE;
        if (access & Access.execute) flags |= FILE_MAP_EXECUTE;
        return flags;
    }
}
else
{
    static assert(false, "Not implemented on this platform.");
}

/**
 * A memory mapped file. This essentially allows a file to be used as if it were
 * a slice of memory. For many use cases, it is a very efficient means of
 * accessing a file.
 */
private struct MemoryMapImpl(T)
{
    // Memory mapped data.
    T[] data;

    alias data this;

    version (Windows)
        private HANDLE fileMap = null;

    /**
     * Maps the contents of the specified file into memory.
     *
     * Params:
     *   file = Open file to be mapped. The file may be closed after being
     *          mapped to memory. The file must not be a terminal or a pipe. It
     *          must have random access capabilities.
     *   access = Access flags of the memory region. Read-only access by
     *            default.
     *   length = Length of the memory map in number of $(D T). If 0, the length
     *            is taken to be the size of the file. 0 by default.
     *   start = Offset within the file to start the mapping in bytes. 0 by
     *           default.
     *   share = If true, changes are visible to other processes. If false,
     *           changes are not visible to other processes and are never
     *           written back to the file. True by default.
     *   address = The preferred memory address to map the file to. This is just
     *             a hint, the system is may or may not use this address. If
     *             null, the system chooses an appropriate address. Null by
     *             default.
     *
     * Throws: SysException if the memory map could not be created.
     */
    this(File file, Access access = Access.read, size_t length = 0,
        long start = 0, bool share = true, void* address = null)
    {
        import std.conv : to;

        if (length == 0)
            length = (file.length - start).to!size_t / T.sizeof;

        version (Posix)
        {
            int flags = share ? MAP_SHARED : MAP_PRIVATE;

            auto p = cast(T*)mmap(
                address,                // Preferred base address
                length * T.sizeof,      // Length of the memory map
                access.protectionFlags, // Protection flags
                flags,                  // Mapping flags
                file.handle,            // File descriptor
                cast(off_t)start        // Offset within the file
                );

            sysEnforce(p != MAP_FAILED, "Failed to map file to memory");

            data = p[0 .. length];
        }
        else version (Windows)
        {
            immutable ULARGE_INTEGER maxSize =
                {QuadPart: cast(ulong)(length * T.sizeof)};

            // Create the file mapping object
            fileMap = CreateFileMappingW(
                file.handle,            // File handle
                null,                   // Security attributes
                access.protectionFlags, // Page protection flags
                maxSize.HighPart,       // Maximum size (high-order bytes)
                maxSize.LowPart,        // Maximum size (low-order bytes)
                null                    // Optional name to give the object
                );

            sysEnforce(fileMap, "Failed to create file mapping object");

            scope(failure) CloseHandle(fileMap);

            immutable ULARGE_INTEGER offset = {QuadPart: cast(ulong)start};

            // Create a view into the file mapping
            auto p = cast(T*)MapViewOfFileEx(
                fileMap,             // File mapping object
                access.mapViewFlags, // Desired access
                offset.HighPart,     // File offset (high-order bytes)
                offset.LowPart,      // File offset (low-order bytes)
                length * T.sizeof,   // Number of bytes to map
                address,             // Preferred base address
                );

            sysEnforce(p, "Failed to map file to memory");

            data = p[0 .. length];
        }
    }

    /**
     * Unmaps the file from memory and writes back any changes to the file
     * system.
     */
    ~this()
    {
        if (data is null) return;

        version (Posix)
        {
            sysEnforce(
                munmap(data.ptr, data.length * T.sizeof) == 0,
                "Failed to unmap memory"
                );
        }
        else version (Windows)
        {
            sysEnforce(
                UnmapViewOfFile(data.ptr) != 0,
                "Failed to unmap memory"
                );
            sysEnforce(
                CloseHandle(fileMap),
                "Failed to close file map object handle"
                );
        }
    }

    /**
     * Synchronously writes any pending changes to the file on the file system.
     */
    void flush()
    {
        version (Posix)
        {
            sysEnforce(
                msync(data.ptr, data.length * T.sizeof, MS_SYNC) == 0,
                "Failed to flush memory map"
                );
        }
        else version (Windows)
        {
            // TODO: Make this synchronous
            sysEnforce(
                FlushViewOfFile(data.ptr, data.length * T.sizeof) != 0,
                "Failed to flush memory map"
                );
        }
    }

    /**
     * Asynchronously writes any pending changes to the file on the file system.
     */
    void flushAsync()
    {
        version (Posix)
        {
            sysEnforce(
                msync(data.ptr, data.length * T.sizeof, MS_ASYNC) == 0,
                "Failed to flush memory map"
                );
        }
        else version (Windows)
        {
            sysEnforce(
                FlushViewOfFile(data.ptr, data.length * T.sizeof) != 0,
                "Failed to flush memory map"
                );
        }
    }

    // Disable appends. It is possible to use mremap() on Linux to extend (or
    // contract) the length of the map. However, this is not a portable feature.
    @disable void opOpAssign(string op = "~")(const(T)[] rhs);
}

import std.typecons;
alias MemoryMap(T) = RefCounted!(MemoryMapImpl!T, RefCountedAutoInitialize.no);

/**
 * Convenience function for creating a memory map.
 */
auto memoryMap(T)(File file, Access access = Access.read,
    size_t length = 0, long start = 0, bool share = true,
    void* address = null)
{
    return MemoryMap!T(file, access, length, start, share, address);
}

///
unittest
{
    auto tf = testFile();

    immutable newData = "The quick brown fox jumps over the lazy dog.";

    // Modify the file
    {
        auto f = File(tf.name, FileFlags.readWriteEmpty);
        f.length = newData.length;

        auto map = f.memoryMap!char(Access.readWrite);
        assert(map.length == newData.length);

        map[] = newData[];

        assert(map[0 .. newData.length] == newData[]);
    }

    // Read the file back in
    {
        auto f = File(tf.name, FileFlags.readExisting);
        auto map = f.memoryMap!char(Access.read);
        assert(map.length == newData.length);
        assert(map[0 .. newData.length] == newData[]);
    }
}

unittest
{
    import std.range : ElementType;
    static assert(is(ElementType!(MemoryMap!size_t) == size_t));
}

unittest
{
    import std.exception;

    auto tf = testFile();

    auto f = File(tf.name, FileFlags.readWriteEmpty);
    assert(f.length == 0);
    assert(collectException!SysException(f.memoryMap!char(Access.readWrite)));
}

unittest
{
    import io.file.temp;

    immutable int[] data = [4, 8, 15, 16, 23, 42];

    auto f = tempFile.file;
    f.length = data.length * int.sizeof;

    auto map = f.memoryMap!int(Access.readWrite);
    map[] = data;
    assert(map[] == data);
    assert(map ~ [100, 200] == data ~ [100, 200]);
}

unittest
{
    import io.file.temp;
    import std.parallelism, std.random;

    immutable N = 1024;

    auto f = tempFile.file;
    f.length = size_t.sizeof * N;

    auto map = f.memoryMap!size_t(Access.readWrite);
    assert(map.length == N);

    foreach (i, ref e; parallel(map[]))
        e = uniform!"[]"(size_t.min, size_t.max);
}
