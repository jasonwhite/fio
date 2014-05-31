/**
 * Copyright: Copyright Jason White, 2013-
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
    static assert(false, "Not implemented yet.");
}


/**
 * A memory mapped file.
 */
struct MmFile
{
    // Memory mapped data.
    private void[] data;

    alias data this;

    alias Position = File.Position;
    alias Offset   = File.Offset;

    // Converts the Access enum to POSIX protection flags.
    version (Posix)
    static private int prot(Access access) pure nothrow
    {
        int prot = PROT_NONE;
        if (access & Access.read)    prot |= PROT_READ;
        if (access & Access.write)   prot |= PROT_WRITE;
        if (access & Access.execute) prot |= PROT_EXEC;
        return prot;
    }

    /**
     * Maps the contents of the specified file into memory.
     *
     * Params:
     *   file = Open file to be mapped. The file may be closed after being
     *      mapped to memory.
     *   access = Access flags of the memory region.
     *   length = Length of the file. If 0, the length is taken to be the size
     *      of the file minus the offset.
     *   offset = Position within the file to start the mapping. This must be
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
    this()(auto ref File file, size_t length = 0, Position offset = 0,
            Access access = Access.readWrite, bool share = true,
            void* address = null)
    {
        version (Posix)
        {
            if (length == 0)
                length = file.length - offset;

            int flags = share ? MAP_SHARED : MAP_PRIVATE;

            void *p = mmap(
                address,          // Preferred address
                length,           // Length of the memory map
                prot(access),     // Protection flags
                flags,            // Mapping flags
                file.handle,      // File descriptor
                cast(off_t)offset // Offset within the file (must be page-aligned)
                );

            sysEnforce(p != MAP_FAILED, "Failed to map file to memory");

            data = p[0 .. length];
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
            int ret = munmap(data.ptr, data.length);
            sysEnforce(ret == 0, "Failed to unmap memory");
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
     * Write any pending changes to the file on the file system.
     */
    void sync()
    {
        version (Posix)
        {
            int ret = msync(data.ptr, data.length, MS_SYNC);
            sysEnforce(ret == 0, "Failed to synchronize memory map");
        }
    }
}

unittest
{
    auto tf = testFile();

    {
        auto map = File(tf.name, FileFlags.writeEmpty)
            .MmFile(128, 0);

        auto text = cast(char[])map;

        immutable newdata = "The quick brown fox jumps over the lazy dog.";

        text[0 .. newdata.length] = newdata[];
    }
}
