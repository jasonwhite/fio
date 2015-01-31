/**
 * Copyright: Copyright Jason White, 2014
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
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
    import std.c.windows.windows;
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
final class MemoryMap
{
    // Memory mapped data.
    void[] data;

    version (Windows)
        private HANDLE fileMap = null;

    alias data this;

    /**
     * Maps the contents of the specified file into memory.
     *
     * Params:
     *   file = Open file to be mapped. The file may be closed after being
     *          mapped to memory. The file must not be a terminal or a pipe. It
     *          must have random access capabilities.
     *   access = Access flags of the memory region. Read-only access by
     *            default.
     *   length = Length of the file. If 0, the length is taken to be the size
     *            of the file. 0 by default.
     *   start = Position within the file to start the mapping. This must be
     *           a multiple of the page size (generally 4096). 0 by default.
     *   share = If true, changes are visible to other processes. If false,
     *           changes are not visible to other processes and are never
     *           written back to the file. True by default.
     *   address = The preferred memory address to map the file to. This is just
     *             a hint, the system is may or may not use this address. If
     *             null, the system chooses an appropriate address. Null by
     *             default.
     *
     * Throws: SysException
     */
    this(File file, Access access = Access.read, size_t length = 0,
        File.Position start = 0, bool share = true, void* address = null)
    {
        version (Posix)
        {
            if (length == 0)
                length = file.length;

            // POSIX does not allow the file to be empty. mmap will catch this
            // error as "Invalid argument", but since this is a common-enough
            // case, we handle it here with a better error message.
            sysEnforce(length != 0, "Cannot map empty file.");

            int flags = share ? MAP_SHARED : MAP_PRIVATE;

            void *p = mmap(
                address,                // Preferred address
                length,                 // Length of the memory map
                access.protectionFlags, // Protection flags
                flags,                  // Mapping flags
                file.handle,            // File descriptor
                cast(off_t)start        // Offset within the file (must be page-aligned)
                );

            sysEnforce(p != MAP_FAILED, "Failed to map file to memory");

            data = p[0 .. length];
        }
        else version (Windows)
        {
            // TODO
            //auto fileMapping = CreateFileMappingA(file.handle, null, );
            static assert(false, "Implement me!");
        }
    }

    /**
     * Checks if the file is mapped.
     */
    @property bool isMapped() const pure nothrow
    {
        return data !is null;
    }

    /**
     * An anonymous mapping. An anonymous mapping is not backed by any file. Its
     * contents are initialized to 0. This is equivalent to allocating memory.
     */
    /*this(Access access, size_t length, bool share = true, void* address = null)
    {
        version (Posix)
        {
            int flags = MAP_ANON | (share ? MAP_SHARED : MAP_PRIVATE);
            void *p = mmap(address, length, prot(access), flags, -1, 0);
            sysEnforce(p != MAP_FAILED, "Failed to memory map file");

            data = p[0 .. length];
        }
    }*/

    /**
     * Unmaps the file from memory and writes back any changes to the file
     * system.
     */
    ~this()
    {
        if (!isMapped) return;

        version (Posix)
        {
            sysEnforce(
                munmap(data.ptr, data.length) == 0,
                "Failed to unmap memory"
                );
        }
        else version (Windows)
        {
            sysEnforce(
                UnmapViewOfFile(data.ptr) != 0,
                "Failed to unmap memory"
                );
        }
    }

    /*void remap(size_t length, size_t offset = 0, bool share = true)
    {
        version (Posix)
        {
            int flags = (share ? MAP_SHARED : MAP_PRIVATE);
            void *p = mremap(data.ptr, data.length, length, flags);
            sysEnforce(ret == 0, "Failed to remap memory");
        }
    }*/

    /**
     * Synchronously writes any pending changes to the file on the file system.
     */
    void flush()
    in { assert(isMapped); }
    body
    {
        version (Posix)
        {
            sysEnforce(
                msync(data.ptr, data.length, MS_SYNC) == 0,
                "Failed to flush memory map"
                );
        }
        else version (Windows)
        {
            // TODO: Make this synchronous
            sysEnforce(
                FlushViewOfFile(data.ptr, data.length) != 0,
                "Failed to flush memory map"
                );
        }
    }

    /**
     * Asynchronously writes any pending changes to the file on the file system.
     */
    void flushAsync()
    in { assert(isMapped); }
    body
    {
        version (Posix)
        {
            sysEnforce(
                msync(data.ptr, data.length, MS_ASYNC) == 0,
                "Failed to flush memory map"
                );
        }
        else version (Windows)
        {
            sysEnforce(
                FlushViewOfFile(data.ptr, data.length) != 0,
                "Failed to flush memory map"
                );
        }
    }
}

/**
 * Convenience function for creating a memory map.
 */
MemoryMap memoryMap(File file, Access access = Access.read,
        size_t length = 0, File.Position start = 0, bool share = true,
        void* address = null)
{
    return new MemoryMap(file, access, length, start, share, address);
}

///
unittest
{
    auto tf = testFile();

    immutable newData = "The quick brown fox jumps over the lazy dog.";

    // Modify the file
    {
        auto f = new File(tf.name, FileFlags.readWriteEmpty);
        f.length = newData.length;

        auto map = f.memoryMap(Access.readWrite);
        auto data = cast(char[])map;

        data[0 .. newData.length] = newData[];

        assert(data[0 .. newData.length] == newData[]);
    }

    // Read the file back in
    {
        auto map = new File(tf.name, FileFlags.readExisting).memoryMap();
        auto data = cast(char[])map;
        assert(data[0 .. newData.length] == newData[]);
    }
}

unittest
{
    import std.exception;

    auto tf = testFile();

    auto f = new File(tf.name, FileFlags.readWriteEmpty);
    assert(f.length == 0);
    assert(collectException!SysException(f.memoryMap(Access.readWrite)));
}
