/**
 * Copyright: Copyright Jason White, 2014
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.file.flags;

/**
 * Specifies in what mode a file should be opened.
 */
enum Mode
{
    /// Default mode. Not very useful.
    none = 0,

    /**
     * Opens an existing file. Unless combined with create, fails if the file
     * does not exist.
     */
    open = 1 << 0,

    /**
     * Creates a new file. Fails if the file is opened without write access.
     * Fails if the file already exists and not combined with truncate or open.
     */
    create = 1 << 1,

    /**
     * Opens the file if it already exists or creates it if it does not.
     */
    openOrCreate = open | create,

    /**
     * Allows only appending to the end of the file. Seek operations only affect
     * subsequent reads. Upon writing, the file pointer gets set to the end of
     * the file.
     */
    append = 1 << 2,

    /**
     * Truncates the file. This has no effect if the file has been created anew.
     * Fails if the file is opened without write access.
     */
    truncate = 1 << 3,
}

/**
 * Specifies how to access the file.
 */
enum Access
{
    /// Default access. Not very useful.
    none = 0,

    /// Allows only read operations on the file.
    read = 1 << 0,

    /// Allows only write operations on the file.
    write = 1 << 1,

    /// Allows data to be executed. This is only used for memory mapped files.
    execute = 1 << 2,

    /// Allows both read and write operations on the file.
    readWrite = read | write,
}

/**
 * Specifies what other processes are allowed to do to the file.
 *
 * TODO: Keep this? It's currently only used by Windows.
 */
enum Share
{
    /// Forbids sharing of the file.
    none = 0,

    /// Allows others to read from the file.
    read = 1 << 0,

    /// Allows others to write to the file.
    write = 1 << 1,

    /// Allows others to either read or write to the file.
    readWrite = read | write,

    /// Allows the file to deleted.
    remove = 1 << 2,
}

/**
 * File flags determine how a file stream is created and used.
 *
 * TODO: Store native file flags instead.
 */
struct FileFlags
{
    /**
     * Typical file flag configurations. These are converted to the underlying
     * platform-specific file flags at compile-time. Thus, there is zero
     * overhead to using these pre-defined file flags.
     */
    static immutable
    {
        /**
         * An existing file is opened with read access. This is likely the most
         * commonly used set of flags.
         */
        FileFlags readExisting = FileFlags(Mode.open, Access.read);

        /**
         * An existing file is opened with write access.
         */
        FileFlags writeExisting = FileFlags(Mode.open, Access.write);

        /**
         * A new file is created with write access.
         */
        FileFlags writeNew = FileFlags(Mode.create, Access.write);

        /**
         * A new file is either opened or created with write access.
         */
        FileFlags writeAlways = FileFlags(Mode.openOrCreate, Access.write);

        /**
         * A new file is either opened or created, truncated if necessary, with
         * write access. This ensures that an $(I empty) file is opened.
         */
        FileFlags writeEmpty = FileFlags(Mode.openOrCreate | Mode.truncate, Access.write);

        /**
         * An existing file is opened with read/write access.
         */
        FileFlags readWriteExisting = FileFlags(Mode.open, Access.readWrite);

        /**
         * A new file is created with read/write access.
         */
        FileFlags readWriteNew = FileFlags(Mode.create, Access.readWrite);

        /**
         * A new file is either opened or created with read/write access.
         */
        FileFlags readWriteAlways = FileFlags(Mode.openOrCreate, Access.readWrite);

        /**
         * A new file is either opened or created, truncated if necessary, with
         * read/write access. This ensures that an $(I empty) file is opened.
         */
        FileFlags readWriteEmpty = FileFlags(Mode.openOrCreate | Mode.truncate, Access.readWrite);
    }

    version (Posix)
    {
        import core.sys.posix.fcntl;

        int flags;

        this(Mode mode = Mode.init,
             Access access = Access.init,
             Share share = Share.init) pure nothrow
        {
            // Disable buffering. Buffering is handled by $(D io.buffered).
            //flags |= O_DIRECT; // FIXME: O_DIRECT is not defined

            if ((mode & Mode.openOrCreate) == Mode.openOrCreate)
                flags |= O_CREAT;
            else if (mode & Mode.create)
                flags |= O_EXCL | O_CREAT;
            // Mode.open by default

            if (mode & Mode.truncate)
                flags |= O_TRUNC;

            if (mode & Mode.append)
                flags |= O_APPEND;

            if (access == Access.readWrite)
                flags |= O_RDWR;
            else if (access & Access.read)
                flags |= O_RDONLY;
            else if (access & Access.write)
                flags |= O_WRONLY;

            // Share flags are unused.
        }

        unittest
        {
            with (FileFlags)
            {
                static assert(readExisting.flags      == O_RDONLY);
                static assert(writeExisting.flags     == O_WRONLY);
                static assert(writeNew.flags          == (O_EXCL | O_CREAT | O_WRONLY));
                static assert(writeAlways.flags       == (O_CREAT | O_WRONLY));
                static assert(writeEmpty.flags        == (O_CREAT | O_TRUNC | O_WRONLY));
                static assert(readWriteExisting.flags == O_RDWR);
                static assert(readWriteNew.flags      == (O_CREAT | O_EXCL | O_RDWR));
                static assert(readWriteAlways.flags   == (O_CREAT | O_RDWR));
                static assert(readWriteEmpty.flags    == (O_CREAT | O_RDWR | O_TRUNC));
            }
        }
    }
    else version (Windows)
    {
        import core.sys.windows.windows;

        DWORD access, share, mode;

        this(Mode mode = Mode.init,
             Access access = Access.init,
             Share share = Share.init) pure nothrow
        {
            // Access flags
            if (access & Access.read)
                this.access |= GENERIC_READ;
            if (access & Access.write)
                this.access |= GENERIC_WRITE;
            if (mode & Mode.append)
                this.access |= FILE_APPEND_DATA;

            // Share flags
            if (share & Share.read)
                this.share |= FILE_SHARE_READ;
            if (share & Share.write)
                this.share |= FILE_SHARE_WRITE;
            if (share & Share.remove)
                this.share |= FILE_SHARE_DELETE;

            // Creation flags
            if (mode & Mode.truncate)
            {
                if (mode & Mode.create)
                    this.mode = CREATE_ALWAYS;
                else
                    this.mode = TRUNCATE_EXISTING;
            }
            else if ((mode & Mode.openOrCreate) == Mode.openOrCreate)
                this.mode = OPEN_ALWAYS;
            else if (mode & Mode.open)
                this.mode = OPEN_EXISTING;
            else if (mode & Mode.create)
                this.mode = CREATE_NEW;
        }
    }

    /**
     * Construct the file flags from a mode string.
     */
    this(string mode) pure
    {
        this = parse(mode);
    }

    /**
     * Set flags via a mode string.
     */
    void opAssign(string mode) pure
    {
        this = parse(mode);
    }

    unittest
    {
        FileFlags ff;
        ff = "w+";
        assert(ff == FileFlags.readWriteEmpty);
        assert(ff == FileFlags("w+"));
    }

    /**
     * Parses an fopen-style mode string such as "r+".
     *
     * It is not advisable to use fopen-style mode strings. It is better to use
     * one of the predefined file flag configurations such as $(D
     * FileFlags.readExisting) for greater readability and intent of meaning.
     */
    static FileFlags parse(string s) pure
    {
        import std.range : front, popFront, empty;

        if (s.empty)
            throw new Exception("Expected non-empty mode string");

        Mode mode;
        Access access;
        Share share;

        switch (s.front)
        {
            case 'r':
                access = Access.read;
                mode   = Mode.open;
                break;
            case 'w':
                access = Access.write;
                mode   = Mode.openOrCreate | Mode.truncate;
                break;
            case 'a':
                access = Access.write;
                mode   = Mode.create | Mode.append;
                break;
            default:
                throw new Exception("Expected 'r', 'w', or 'a' in mode string");
        }

        s.popFront();

        // Note that the binary flag is ignored. Here, file streams are always
        // binary streams. Text functionality is accessed via $(D io.text)
        // instead.
        foreach (i; 0 .. 2)
        {
            if (s.empty) return FileFlags(mode, access, share);

            switch (s.front)
            {
                case 'b':
                    // Ignored
                    break;
                case '+':
                    access = Access.readWrite;
                    break;
                default:
                    throw new Exception("Expected 'b' or '+' in mode string");
            }

            s.popFront();
        }

        if (!s.empty)
            throw new Exception("Expected end of mode string");

        return FileFlags(mode, access, share);
    }

    ///
    unittest
    {
        static assert(FileFlags("r") == FileFlags.readExisting);
        static assert(FileFlags("w") == FileFlags.writeEmpty);
        static assert(FileFlags("a") == FileFlags(Mode.create | Mode.append, Access.write));

        static assert(FileFlags("r+") == FileFlags.readWriteExisting);
        static assert(FileFlags("w+") == FileFlags.readWriteEmpty);
        static assert(FileFlags("a+") == FileFlags(Mode.create | Mode.append, Access.readWrite));
    }

    unittest
    {
        // Equivalent modes
        static assert(FileFlags("w+") == FileFlags("wb+"));
        static assert(FileFlags("r+") == FileFlags("rb+"));
        static assert(FileFlags("a+") == FileFlags("ab+"));
        static assert(FileFlags("w+b") == FileFlags("wb+"));
        static assert(FileFlags("r+b") == FileFlags("rb+"));
        static assert(FileFlags("a+b") == FileFlags("ab+"));
    }

    unittest
    {
        import std.exception : collectException;

        immutable badModes = ["", "rw", "asdf", "+r", "b+", " r", "r+b "];
        foreach (m; badModes)
            assert(collectException(FileFlags(m)));
    }
}
