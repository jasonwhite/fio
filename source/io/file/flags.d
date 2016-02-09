/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.file.flags;

public import io.stream : Access;

/**
 * Specifies in what mode a file should be opened. These flags can be combined.
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
     * the file. Requires write access to the file.
     */
    append = 1 << 2,

    /**
     * Truncates the file. This has no effect if the file has been created anew.
     * Requires write access to the file.
     */
    truncate = 1 << 3,
}

/**
 * Specifies what other processes are allowed to do to the file. These flags can
 * be combined.
 *
 * Windows_specific:
 * Currently only used by Windows.
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
 * File flags that determine how a file stream is created and used.
 *
 * Since all methods in this struct are pure, the high-level configuration flags
 * given here are converted to the platform-specific file flags at compile time.
 *
 * See_Also:
 * $(D io.file.stream)
 *
 * Example:
 * ---
 * // Creates the file "foobar", truncates it, and opens it in write-only mode
 * auto f = File("foobar", FileFlags.writeEmpty);
 * ---
 */
struct FileFlags
{
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
         * A new file is created with write access. Fails if the file already
         * exists.
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
         * A new file is created with read/write access. Fails if the file
         * already exists.
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

        alias flags this;

        /**
         * Constructs the $(D FileFlag) with the given mode, access, and share
         * attributes. These high-level flags are converted to the
         * equivalent platform-specific flags that are needed when opening the
         * file.
         *
         * Params:
         *   mode = Mode the file should be opened in. That is, to open, create,
         *          append, or truncate the file.
         *   access = The permissions on the file stream. That is, read access,
         *            write access, or both.
         *   share = The sharing permissions other processes are allowed on the
         *           file stream when trying to open the same file. By default,
         *           other processes are prevented from opening the file if they
         *           request read, write, or delete access. If you wish to allow
         *           other processes to read the file while it is open in this
         *           process, set this to $(D Share.read). Currently only used
         *           by Windows.
         *
         * Windows_specific:
         * The share parameter is currently only used by Windows.
         *
         * Example:
         * ---
         * immutable flags = FileFlags(Mode.open, Access.read);
         * ---
         */
        this(Mode mode,
             Access access,
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

            // Posix does not support Share flags.
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

        this(Mode mode,
             Access access,
             Share share = Share.init) pure nothrow
        {
            // Access flags
            if (access & Access.read)  this.access |= GENERIC_READ;
            if (access & Access.write) this.access |= GENERIC_WRITE;
            if (mode & Mode.append)    this.access |= FILE_APPEND_DATA;

            // Share flags
            if (share & Share.read)   this.share |= FILE_SHARE_READ;
            if (share & Share.write)  this.share |= FILE_SHARE_WRITE;
            if (share & Share.remove) this.share |= FILE_SHARE_DELETE;

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
     * Constructs the file flags from a mode string.
     *
     * This simply calls $(LREF FileFlags.parse).
     *
     * See_Also:
     * $(LREF FileFlags.parse)
     */
    this(string mode) pure
    {
        this = parse(mode);
    }

    /// Ditto
    void opAssign(string mode) pure
    {
        this = parse(mode);
    }

    ///
    unittest
    {
        FileFlags ff = "wb+";
        assert(ff == FileFlags.readWriteEmpty);
        assert(ff == FileFlags("wb+"));
    }

    /**
     * Parses an fopen-style mode string such as "r+". That all possible mode
     * strings include:
     *
     * $(TABLE
     *     $(TR $(TH Mode String) $(TH Meaning))
     *     $(TR $(TD $(D "wb"))   $(TD Write truncated))
     *     $(TR $(TD $(D "wb+"))  $(TD Read/write truncated))
     *     $(TR $(TD $(D "w+b"))  $(TD Read/write truncated))
     *     $(TR $(TD $(D "wbx"))  $(TD Write new))
     *     $(TR $(TD $(D "wb+x")) $(TD Read/write new))
     *     $(TR $(TD $(D "w+bx")) $(TD Read/write new))
     *     $(TR $(TD $(D "rb"))   $(TD Read existing"))
     *     $(TR $(TD $(D "rb+"))  $(TD Read/write existing"))
     *     $(TR $(TD $(D "r+b"))  $(TD Read/write existing"))
     *     $(TR $(TD $(D "ab"))   $(TD Append new"))
     *     $(TR $(TD $(D "ab+"))  $(TD Append/read new"))
     *     $(TR $(TD $(D "a+b"))  $(TD Append/read new"))
     * )
     *
     * The _mode strings accepted here differ from those accepted by $(D fopen).
     * Here, file streams are never opened in text _mode -- only binary mode.
     * Text handling functionality is built on top of low-level file streams.
     * It does not make sense to distinguish between text and binary modes here.
     * $(D fopen) opens all files in text _mode by default and the flag 'b' must
     * be specified in order to open in binary _mode. Thus, an exception is
     * thrown here if 'b' is omitted in the specified mode string.
     *
     * Note: It is not advisable to use fopen-style _mode strings. It is better
     * to use one of the predefined file flag configurations such as
     * $(LREF FileFlags.readExisting) for greater readability and intent of
     * meaning.
     */
    static FileFlags parse(string mode) pure
    {
        // There are only 12 possible permutations of mode strings that we care
        // about. (There would be twice as many if the 'b' flag was optional.)
        // Thus, it is easier to just check for all 12 possible flags rather
        // than actually parsing the string.
        switch (mode)
        {
            case "wb":   return FileFlags.writeEmpty;
            case "wb+":  return FileFlags.readWriteEmpty;
            case "w+b":  return FileFlags.readWriteEmpty;
            case "wbx":  return FileFlags.writeNew;
            case "wb+x": return FileFlags.readWriteNew;
            case "w+bx": return FileFlags.readWriteNew;
            case "rb":   return FileFlags.readExisting;
            case "rb+":  return FileFlags.readWriteExisting;
            case "r+b":  return FileFlags.readWriteExisting;
            case "ab":   return FileFlags(Mode.openOrCreate | Mode.append, Access.write);
            case "ab+":  return FileFlags(Mode.openOrCreate | Mode.append, Access.readWrite);
            case "a+b":  return FileFlags(Mode.openOrCreate | Mode.append, Access.readWrite);
            default:
                throw new Exception("Invalid mode string");
        }
    }

    ///
    unittest
    {
        static assert(FileFlags("wb")   == FileFlags.writeEmpty);
        static assert(FileFlags("wb+")  == FileFlags.readWriteEmpty);
        static assert(FileFlags("w+b")  == FileFlags.readWriteEmpty);
        static assert(FileFlags("wbx")  == FileFlags.writeNew);
        static assert(FileFlags("wb+x") == FileFlags.readWriteNew);
        static assert(FileFlags("w+bx") == FileFlags.readWriteNew);
        static assert(FileFlags("rb")   == FileFlags.readExisting);
        static assert(FileFlags("rb+")  == FileFlags.readWriteExisting);
        static assert(FileFlags("r+b")  == FileFlags.readWriteExisting);
        static assert(FileFlags("ab")   == FileFlags(Mode.openOrCreate | Mode.append, Access.write));
        static assert(FileFlags("ab+")  == FileFlags(Mode.openOrCreate | Mode.append, Access.readWrite));
        static assert(FileFlags("a+b")  == FileFlags(Mode.openOrCreate | Mode.append, Access.readWrite));
    }

    unittest
    {
        import std.exception : collectException;

        immutable badModes = ["", "rw", "asdf", "+r", "b+", " r", "r+b "];
        foreach (m; badModes)
            assert(collectException(FileFlags(m)));
    }
}
