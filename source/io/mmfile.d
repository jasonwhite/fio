/**
 * Copyright: Copyright Jason White, 2014
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.mmfile;

import io.file;


version (Posix)
{
    import core.sys.posix.sys.mman;
}
else version (Windows)
{
    import std.c.windows.windows;
}
else
{
    static assert(false, "Not implemented on this platform.");
}


// Converts file access flags to POSIX protection flags.
private @property int prot(Access access) pure nothrow
{
    int prot = PROT_NONE;
    if (access & Access.read)    prot |= PROT_READ;
    if (access & Access.write)   prot |= PROT_WRITE;
    if (access & Access.execute) prot |= PROT_EXEC;
    return prot;
}

/**
 * A memory mapped file. This essentially allows a file to be used as if it were
 * a slice of memory. For many use cases, it is a very efficient means of
 * accessing a file.
 */
struct MmFile
{
    // Memory mapped data.
    void[] data;

    version (Windows)
    private HANDLE fileMap = null;

    alias data this;

    alias Position = File.Position;


    /**
     * Maps the contents of the specified file into memory.
     *
     * Params:
     *   file = Open file to be mapped. The file may be closed after being
     *      mapped to memory. The file must not be a terminal or a pipe. It must
     *      have random access capabilities.
     *   access = Access flags of the memory region.
     *   length = Length of the file. If 0, the length is taken to be the size
     *      of the file.
     *   start = Position within the file to start the mapping. This must be
     *      a multiple of the page size (generally 4096).
     *   share = If true, changes are visible to other processes. If false,
     *      changes are not visible to other processes and are never written
     *      back to the file. True by default.
     *   address = The preferred memory address to map the file to. This is just
     *      a hint, the system is may or may not use this address. If null, the
     *      system chooses an appropriate address.
     *
     * Throws: SysException
     */
    this()(auto ref File file, Access access = Access.read, size_t length = 0,
            Position start = 0, bool share = true, void* address = null)
    {
        version (Posix)
        {
            if (length == 0)
                length = file.length;

            int flags = share ? MAP_SHARED : MAP_PRIVATE;

            void *p = mmap(
                address,         // Preferred address
                length,          // Length of the memory map
                access.prot,     // Protection flags
                flags,           // Mapping flags
                file.handle,     // File descriptor
                cast(off_t)start // Offset within the file (must be page-aligned)
                );

            sysEnforce(p != MAP_FAILED, "Failed to map file to memory");

            data = p[0 .. length];
        }
        else version (Windows)
        {
            //auto fileMapping = CreateFileMappingA(file.handle, null, );
        }
    }

    /**
     * An anonymous mapping. An anonymous mapping is not backed by any file. Its
     * contents are initialized to 0. This is effectively equivalent to
     * allocating memory.
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

    /**
     * TODO: Write a description.
     */
    /*void remap(size_t length, size_t offset = 0, bool share = true)
    {
        version (Posix)
        {
            int flags = (share ? MAP_SHARED : MAP_PRIVATE);
            void *p = mremap(data.ptr, data.length, flags, -1, offset);
            sysEnforce(ret == 0, "Failed to remap memory");
        }
    }*/

    /**
     * Synchronously writes any pending changes to the file on the file system.
     */
    void flush()
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

unittest
{
    auto tf = testFile();

    immutable newData = "The quick brown fox jumps over the lazy dog.";

    // Modify the file
    {
        auto f = File(tf.name, FileFlags.readWriteEmpty);
        f.length = newData.length;

        auto map = f.MmFile(Access.readWrite);
        auto data = cast(char[])map;

        data[0 .. newData.length] = newData[];

        assert(data[0 .. newData.length] == newData[]);
    }

    // Read the file back in
    {
        auto map = File(tf.name, FileFlags.readExisting).MmFile();
        auto data = cast(char[])map;
        assert(data[0 .. newData.length] == newData[]);
    }
}
