/**
  Copyright: Copyright Jason White, 2013-
  License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
  Authors:   Jason White
 */
module io.file;

version (unittest)
    import file = std.file; // For easy file creation/deletion.

version (Posix)
{
    import core.sys.posix.fcntl;
    import core.sys.posix.unistd;
    import std.exception : ErrnoException;

    enum
    {
        SEEK_SET,
        SEEK_CUR,
        SEEK_END
    }

    alias SysException = ErrnoException;
}
else version (Windows)
{
    import core.sys.windows.windows;

    // These are not declared in core.sys.windows.windows
    extern (Windows) nothrow export
    {
        BOOL SetFilePointerEx(
            HANDLE hFile,
            long liDistanceToMove,
            long* lpNewFilePointer,
            DWORD dwMoveMethod
        );

        BOOL GetFileSizeEx(
            HANDLE hFile,
            long* lpFileSize
        );
    }

    class SysException : Exception
    {
        uint errCode;

        this(string msg, string file = null, size_t line = 0)
        {
            import std.windows.syserror : sysErrorString;
            errCode = GetLastError();
            super(msg ~ " (" ~ sysErrorString(errCode) ~ ")", file, line);
        }
    }
}
else
{
    static assert(false, "Unsupported platform.");
}

private T sysEnforce(T, string file = __FILE__, size_t line = __LINE__)
    (T value, lazy string msg = null)
{
    if (!value) throw new SysException(msg, file, line);
    return value;
}

/**
  A light, cross-platform wrapper around low-level file operations.
 */
struct File
{
    // Platform-specific file handle
    version (Posix)
    {
        alias Handle = int;
        enum Handle InvalidHandle = -1;
    }
    else version (Windows)
    {
        alias Handle = HANDLE;
        enum Handle InvalidHandle = INVALID_HANDLE_VALUE;
    }

    private Handle _h = InvalidHandle;

    /**
      When a $(D File) is copied, the internal file handle is duplicated.
     */
    this(this)
    {
        version (Posix)
        {
            if (_h != InvalidHandle)
                _h = .dup(_h);
        }
        else version (Windows)
        {
            static assert(0, "Not implemented yet.");
        }
    }

    unittest
    {
        auto tf = testFile();

        File a;

        {
            auto b = File(tf.name, FileFlags.writeAlways);
            a = b; // Copy
            b.write("abcd");
        }

        assert(a.position == 4);
    }

    /**
      Opens a file by name. By default, an existing file is opened in read mode.
     */
    void open(string name, FileFlags flags = FileFlags.readExisting)
    {
        close();

        version (Posix)
        {
            import std.string : toStringz;

            _h = .open(toStringz(name), flags.posixFlags, 0b110_110_110);
        }
        else version (Windows)
        {
            import std.utf : toUTF16z;

            with (flags.windowsFlags)
            {
                _h = .CreateFileW(
                    toUTF16z(name),        // File name
                    access,                // Desired access
                    share,                 // Share mode
                    null,                  // Security attributes
                    mode,                  // Creation disposition
                    FILE_ATTRIBUTE_NORMAL, // Flags and attributes
                    null,                  // Template file
                    );
            }
        }

        sysEnforce(_h != InvalidHandle, "Could not open file '"~ name ~"'");
    }

    /// Ditto
    this(string name, FileFlags flags = FileFlags.readExisting)
    {
        open(name, flags);
    }

    /**
      Takes control of a file handle.

      It is assumed that we have exclusive control over the file handle and will
      be closed upon destruction as usual.

      This function is useful in a couple of situations:
      $(UL
        $(LI
          The file must be opened with flags that cannot be obtained via $(D
          FileFlags)
        )
        $(LI
          A special file handle must be opened (e.g., $(D stdout), a pipe).
        )
      )

      Params:
        h = The handle to assume control over. For Posix, this is a file
            descriptor ($(D int)). For Windows, this is an object handle ($(D
            HANDLE)).
     */
    void open(typeof(_h) h)
    {
        _h = h;
    }

    /// Ditto
    this(typeof(_h) h)
    {
        open(h);
    }

    unittest
    {
        import std.exception : ce = collectException;

        // Ensure files are opened the way they are supposed to be opened.

        immutable data = "12345678";
        ubyte[data.length] buf;

        auto tf = testFile();

        // Make sure the file does *not* exist
        try .file.remove(tf.name); catch (Exception e) {}

        assert( File(tf.name, FileFlags.readExisting).ce);
        assert( File(tf.name, FileFlags.writeExisting).ce);
        assert(!File(tf.name, FileFlags.writeNew).ce);
        assert(!File(tf.name, FileFlags.writeAlways).ce);

        // Make sure the file *does* exist.
        .file.write(tf.name, data);

        assert(!File(tf.name, FileFlags.readExisting).ce);
        assert(!File(tf.name, FileFlags.writeExisting).ce);
        assert( File(tf.name, FileFlags.writeNew).ce);
        assert(!File(tf.name, FileFlags.writeAlways).ce);
    }

    /**
      Opens a temporary file.
     */
    void open(FileFlags flags)
    {
        close();

        // TODO: Generate a random name

        version (Posix)
        {
            // TODO: Open the file and unlink the file name.
        }
        else version (Windows)
        {
            // TODO: ???
        }
    }

    this(FileFlags flags)
    {
        open(flags);
    }

    /**
      Closes the file stream. Typically, it is better to let the destructor take
      care of closing the file.
     */
    void close()
    {
        if (_h == InvalidHandle) return; // Not open

        version (Posix)
        {
            sysEnforce(.close(_h) != -1, "Failed to close file");
        }
        else version (Windows)
        {
            sysEnforce(CloseHandle(_h), "Failed to close file");
        }

        _h = InvalidHandle;
    }

    /// Ditto
    ~this()
    {
        close();
    }

    /**
      Returns true if the file is open.
     */
    @property bool isOpen() const pure nothrow
    {
        return _h != InvalidHandle;
    }

    unittest
    {
        auto tf = testFile();

        File f;
        assert(!f.isOpen);
        f.open(tf.name, FileFlags.writeAlways);
        assert(f.isOpen);
    }

    /**
      Returns the internal file handle.
     */
    @property const(typeof(_h)) handle() const pure nothrow
    in { assert(isOpen); }
    body
    {
        return _h;
    }

    /**
      Read data from the file.
     */
    T[] read(T)(T[] buf)
    in { assert(isOpen); }
    body
    {
        version (Posix)
        {
            auto n = .read(_h, buf.ptr, buf.length * T.sizeof);
            sysEnforce(n != -1);
            return buf[0 .. n/T.sizeof];
        }
        else version (Windows)
        {
            DWORD n = void;
            sysEnforce(ReadFile(_h, buf.ptr, buf.length * T.sizeof, &n, null));
            return buf[0 .. n/T.sizeof];
        }
    }

    unittest
    {
        auto tf = testFile();

        immutable data = "\r\n\n\r\n";
        file.write(tf.name, data);

        ubyte[data.length] buf;

        auto f = File(tf.name, FileFlags.readExisting);
        assert(f.read(buf) == data);
    }

    /**
      Write data to the file. Returns the number of bytes written (not the
      number of $(D T)s written).
     */
    size_t write(in void[] data)
    in { assert(isOpen); }
    body
    {
        version (Posix)
        {
            auto n = .write(_h, data.ptr, data.length);
            sysEnforce(n != -1);
            return cast(size_t)n;
        }
        else version (Windows)
        {
            DWORD written = void;
            sysEnforce(
                WriteFile(_h, data.ptr, data.length, &written, null)
                );
            return written;
        }
    }

    unittest
    {
        auto tf = testFile();

        immutable data = "\r\n\n\r\n";

        File(tf.name, FileFlags.writeEmpty).write(data);

        assert(file.read(tf.name) == data);
    }

    /// An absolute position in the file.
    alias Position = ulong;

    /// Special positions.
    static immutable Position
        start = 0,
          end = Position.max;

    /**
      Gets/sets the current position in the file.
     */
    @property Position position()
    {
        return skip(0);
    }

    /// Ditto
    @property void position(Position p)
    {
        seekTo(p);
    }

    /**
      Seeks relative to the current position
     */
    Position skip(long offset)
    {
        return seek(From.here, offset);
    }

    /**
      Seeks relative to a position.
     */
    Position seekTo(Position p, long offset = 0)
    {
        if (p == end)
            return seek(From.end, offset);
        else
            return seek(From.start, offset + p);
    }

    private enum From
    {
        start,
        here,
        end,
    }

    private ulong seek(From from, long offset)
    in { assert(isOpen); }
    body
    {
        version (Posix)
        {
            int whence = void;

            final switch (from)
            {
                case From.start: whence = SEEK_SET; break;
                case From.here:  whence = SEEK_CUR; break;
                case From.end:   whence = SEEK_END; break;
            }

            auto pos = .lseek(_h, offset, whence);
            sysEnforce(pos != -1, "Failed to seek to position");
            return pos;
        }
        else version (Windows)
        {
            DWORD whence = void;

            final switch (from)
            {
                case From.start: whence = FILE_BEGIN;   break;
                case From.here:  whence = FILE_CURRENT; break;
                case From.end:   whence = FILE_END;     break;
            }

            long pos = void;
            sysEnforce(SetFilePointerEx(_h, offset, &pos, whence),
                "Failed to seek to position");
            return pos;
        }
    }

    unittest
    {
        auto tf = testFile();

        auto f = File(tf.name, FileFlags.updateAlways);

        immutable data = "abcdefghijklmnopqrstuvwxyz";
        assert(f.write(data) == data.length);

        assert(f.seekTo(f.start, 5) == 5);
        assert(f.skip(5) == 10);
        assert(f.seekTo(f.end, -5) == data.length - 5);

        // Test large offset
        Position p = cast(long)int.max * 2;
        assert(f.seekTo(f.start, p) == p);
    }

    /**
      Gets the size of the file.
     */
    @property ulong length()
    in { assert(isOpen); }
    body
    {
        version (Windows)
        {
            long size = void;
            sysEnforce(GetFileSizeEx(_h, &size));
            return size;
        }
        else
        {
            // FIXME: This should be an atomic operation
            auto m = position;
            scope (exit) seekTo(m);
            return seekTo(end);
        }
    }

    unittest
    {
        auto tf = testFile();
        auto f = File(tf.name, FileFlags.writeEmpty);

        assert(f.length == 0);

        immutable data = "0123456789";
        assert(f.write(data) == data.length);
        auto m = f.seekTo(3);

        assert(f.length == data.length);

        assert(f.position == m);
    }
}

/**
  Specifies in what mode the file should be opened.
 */
enum Mode
{
    /// Default mode. Not very useful.
    none = 0,

    /**
      Opens an existing file. Unless combined with create, fails if the file
      does not exist.
     */
    open = 1 << 0,

    /**
      Creates a new file. Fails if the file is opened without write access.
      Fails if the file already exists and not combined with truncate or open.
     */
    create = 1 << 1,

    /**
      Opens the file if it already exists or creates it if it does not.
     */
    openOrCreate = open | create,

    /**
      Allows only appending to the end of the file. Seek operations only affect
      subsequent reads. Upon writing, the file pointer gets set to the end of
      the file.
     */
    append = 1 << 2,

    /**
      Truncates the file. This has no effect if the file has been created anew.
      Fails if the file is opened without write access.
     */
    truncate = 1 << 3,
}

/**
  Specifies how to access the file.
 */
enum Access
{
    /// Default access. Not very useful.
    none = 0,

    /// Allows only read operations on the file.
    read = 1 << 0,

    /// Allows only write operations on the file.
    write = 1 << 1,

    /// Allows both read and write operations on the file.
    readWrite = read | write,
}

/**
  Specifies what other processes are allowed to do to the file.

  TODO: Keep this? It's currently only used by Windows.
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
  File flags determine how a file stream is created and used.
 */
struct FileFlags
{
    Mode mode;
    Access access;
    Share share;

    /// Typical file flag configurations:
    static immutable
    {
        /**
          An existing file is opened with read access. This is the most commonly
          used configuration.
         */
        FileFlags readExisting = FileFlags(Mode.open, Access.read);

        /**
          An existing file is opened with write access.
         */
        FileFlags writeExisting = FileFlags(Mode.open, Access.write);

        /**
          A new file is created with write access.
         */
        FileFlags writeNew = FileFlags(Mode.create, Access.write);

        /**
          A new file is either opened or created with write access.
         */
        FileFlags writeAlways = FileFlags(Mode.openOrCreate, Access.write);

        /**
          A new file is either opened or created, truncated if necessary, with write
          access. This ensures that an $(I empty) file is opened.
         */
        FileFlags writeEmpty = FileFlags(Mode.openOrCreate | Mode.truncate, Access.write);

        /**
          An existing file is opened with read/write access.
         */
        FileFlags updateExisting = readExisting | writeExisting;

        /**
          A new file is created with read/write access.
         */
        FileFlags updateNew = FileFlags(Mode.create, Access.readWrite);

        /**
          A new file is either opened or created with read/write access.
         */
        FileFlags updateAlways = readExisting | writeNew;

        /**
          A new file is either opened or created, truncated if necessary, with
          read/write access. This ensures that an $(I empty) file is opened.
         */
        FileFlags updateEmpty = writeEmpty | Access.readWrite;
    }

    /**
      Explicitly set the file mode.
     */
    this(Mode mode = Mode.init,
         Access access = Access.init,
         Share share = Share.init) pure nothrow
    {
        this.mode = mode;
        this.access = access;
        this.share = share;
    }

    /**
      Construct the file flags from a mode string.
     */
    this(string mode) pure
    {
        this = parse(mode);
    }

    /**
      Combine file flags.
     */
    FileFlags opBinary(string op, T)(const T rhs) const pure nothrow
        if (op == "|" && (
            is(T : const FileFlags) || is(T : const Mode) ||
            is(T : const Access) || is(T : const Share)
            ))
    {
        FileFlags ff = this;
        ff |= rhs;
        return ff;
    }

    /// Ditto
    void opOpAssign(string op, T)(const T rhs) pure nothrow
        if (op == "|" && (
            is(T : const FileFlags) || is(T : const Mode) ||
            is(T : const Access) || is(T : const Share)
            ))
    {
        static if (is(T : const FileFlags))
        {
            mode   |= rhs.mode;
            access |= rhs.access;
            share  |= rhs.share;
        }
        else static if (is(T : const Mode))
            mode   |= rhs;
        else static if (is(T : const Access))
            access |= rhs;
        else static if (is(T : const Share))
            share  |= rhs;
    }

    ///
    unittest
    {
        assert(
            (FileFlags(Mode.open, Access.read) |
            FileFlags(Mode.create, Access.write)) ==
            FileFlags(Mode.openOrCreate, Access.readWrite)
            );
    }

    /**
      Set flags via a mode string.
     */
    void opAssign(string mode) pure
    {
        this = parse(mode);
    }

    /**
      Parses an fopen-style mode string such as "rb+".

      The regular expression corresponding to a mode string is
      ---
      [rwa](+b\|b+\|+\|b)\?
      ---
     */
    static FileFlags parse(string s) pure
    {
        import std.range : front, popFront, empty;

        if (s.empty)
            throw new Exception("mode string is empty");

        FileFlags flags = void;
        flags.share = Share.init;

        switch (s.front)
        {
            case 'r':
                flags.access = Access.read;
                flags.mode   = Mode.open;
                break;
            case 'w':
                flags.access = Access.write;
                flags.mode   = Mode.openOrCreate | Mode.truncate;
                break;
            case 'a':
                flags.access = Access.write;
                flags.mode   = Mode.create | Mode.append;
                break;
            default:
                throw new Exception("invalid mode string");
        }

        s.popFront();

        // Note that the binary flag is ignored. Here, file streams are always
        // binary streams. Text functionality is accessed via $(D io.text)
        // instead.
        foreach (i; 0 .. 2)
        {
            if (s.empty) return flags;

            switch (s.front)
            {
                case 'b':
                    break;
                case '+':
                    flags.access = Access.readWrite;
                    break;
                default:
                    throw new Exception("invalid mode string");
            }

            s.popFront();
        }

        if (!s.empty)
            throw new Exception("extraneous characters in mode string");

        return flags;
    }

    unittest
    {
        import std.exception : collectException;

        assert(FileFlags("r") == FileFlags.readExisting);
        assert(FileFlags("w") == FileFlags.writeEmpty);
        assert(FileFlags("a") == (FileFlags.writeNew | Mode.append));

        assert(FileFlags("r+") == FileFlags.updateExisting);
        assert(FileFlags("w+") == FileFlags.updateEmpty);
        assert(FileFlags("a+") == (FileFlags.updateNew | Mode.append));

        // Equivalent modes
        assert(FileFlags("w+") == FileFlags("wb+"));
        assert(FileFlags("r+") == FileFlags("rb+"));
        assert(FileFlags("a+") == FileFlags("ab+"));
        assert(FileFlags("w+b") == FileFlags("wb+"));
        assert(FileFlags("r+b") == FileFlags("rb+"));
        assert(FileFlags("a+b") == FileFlags("ab+"));

        immutable badModes = ["", "rw", "asdf", "+r", "b+", " r", "r+b "];
        foreach (m; badModes)
            assert(collectException(FileFlags(m)));

        FileFlags ff;
        ff = "w+";
        assert(ff == FileFlags("w+"));
    }

    // Platform specific file flags.
    version (Posix)
    package @property int posixFlags() const pure nothrow
    {
        int flags;

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

        return flags;
    }

    else version (Windows)
    @property auto windowsFlags() const pure nothrow
    {
        struct WindowsFlags
        {
            DWORD access;
            DWORD share;
            DWORD mode;
        }

        WindowsFlags flags;

        // Access flags
        if (access & Access.read)
            flags.access |= GENERIC_READ;
        if (access & Access.write)
            flags.access |= GENERIC_WRITE;
        if (mode & Mode.append)
            flags.access |= FILE_APPEND_DATA;

        // Sharing flags
        if (share & Share.read)
            flags.share |= FILE_SHARE_READ;
        if (share & Share.write)
            flags.share |= FILE_SHARE_WRITE;
        if (share & Share.remove)
            flags.share |= FILE_SHARE_DELETE;

        // Creation flags
        if (mode & Mode.truncate)
        {
            if (mode & Mode.create)
                flags.mode = CREATE_ALWAYS;
            else
                flags.mode = TRUNCATE_EXISTING;
        }
        else if ((mode & Mode.openOrCreate) == Mode.openOrCreate)
            flags.mode = OPEN_ALWAYS;
        else if (mode & Mode.open)
            flags.mode = OPEN_EXISTING;
        else if (mode & Mode.create)
            flags.mode = CREATE_NEW;

        return flags;
    }
}

version (unittest)
{
    /**
      Generates a file name for testing and attempts to delete it on
      destruction.
     */
    private auto testFile(string file = __FILE__, size_t line = __LINE__)
    {
        import std.conv : text;
        import std.path : baseName;
        import std.file : tempDir;

        static struct TestFile
        {
            string name;

            alias name this;

            ~this()
            {
                // Don't care if this fails.
                try .file.remove(name); catch (Exception e) {}
            }
        }

        return TestFile(text(tempDir, "/.deleteme-", baseName(file), ".", line));
    }
}
