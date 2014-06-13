/**
 * Copyright: Copyright Jason White, 2014
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.file.stream;

public import io.file.flags;

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

    // FIXME: This should be moved into a separate module.
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

    // FIXME: This should be moved into a separate module.
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

// FIXME: This should be moved into a separate module.
T sysEnforce(T, string file = __FILE__, size_t line = __LINE__)
    (T value, lazy string msg = null)
{
    if (!value) throw new SysException(msg, file, line);
    return value;
}

/**
 * A light-weight, cross-platform wrapper around low-level file operations.
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
     * When a $(D File) is copied, the internal file handle is duplicated.
     *
     * If reference counting is desired instead, wrap $(D File) with $(D
     * RefCounted).
     */
    this(this)
    {
        version (Posix)
        {
            if (isOpen)
                _h = .dup(_h);
        }
        else version (Windows)
        {
            if (isOpen)
            {
                auto proc = GetCurrentProcess();
                auto ret = DuplicateHandle(
                    proc, // Process with the file handle
                    _h,   // Handle to duplicate
                    proc, // Process for the duplicated handle
                    &_h,  // The duplicated handle
                    0,    // Access flags, ignored
                    true, // Allow this handle to be inherited
                    DUPLICATE_SAME_ACCESS
                );
                sysEnforce(ret, "Failed to duplicate handle");
            }
        }
    }

    unittest
    {
        auto tf = testFile();

        auto a = File(tf.name, FileFlags.writeEmpty);

        {
            auto b = a; // Copy
            b.write("abcd");
        }

        assert(a.position == 4);
    }

    unittest
    {
        // File is copied when passed to the function.
        static void foo(File f)
        {
            f.write("abcd");
        }

        auto tf = testFile();
        auto f = File(tf.name, FileFlags.writeEmpty);

        assert(f.position == 0);

        foo(f);

        assert(f.position == 4);
    }

    /**
     * Opens or creates a file by name. By default, an existing file is opened
     * in read-only mode.
     *
     * Params:
     *     name = The name of the file.
     *     flags = How to open the file.
     *
     * Example:
     * ---
     * // Create a brand-new file and write to it. Throws an exception if the
     * // file already exists.
     * auto f = File("filename", FileFlags.writeNew);
     * f.write("Hello world!");
     * ---
     */
    this(string name, FileFlags flags = FileFlags.readExisting)
    {
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
                    null,                  // Template file handle
                    );
            }
        }

        sysEnforce(_h != InvalidHandle, "Failed to open file '"~ name ~"'");
    }

    /**
     * Takes control of a file handle.
     *
     * It is assumed that we have exclusive control over the file handle and will
     * be closed upon destruction as usual.
     *
     * This function is useful in a couple of situations:
     * $(UL
     *   $(LI
     *     The file must be opened with flags that cannot be obtained via $(D
     *     FileFlags)
     *   )
     *   $(LI
     *     A special file handle must be opened (e.g., $(D stdout), a pipe).
     *   )
     * )
     *
     * Params:
     *   h = The handle to assume control over. For Posix, this is a file
     *       descriptor ($(D int)). For Windows, this is an object handle ($(D
     *       HANDLE)).
     */
    this(Handle h)
    {
        _h = h;
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
     * Closes the file stream.
     */
    ~this()
    {
        if (_h == InvalidHandle)
        {
            // Never opened. This happens with default construction.
            return;
        }

        version (Posix)
        {
            sysEnforce(.close(_h) != -1, "Failed to close file");
        }
        else version (Windows)
        {
            sysEnforce(CloseHandle(_h), "Failed to close file");
        }
    }

    /**
     * Returns true if the file is open.
     */
    @property bool isOpen() const pure nothrow
    {
        return _h != InvalidHandle;
    }

    version (none) unittest
    {
        auto tf = testFile();

        File f;
        assert(!f.isOpen);

        f = File(tf.name, FileFlags.writeAlways);
        assert(f.isOpen);
    }

    /**
     * Creates a temporary file. The file is automatically deleted when it is no
     * longer referenced. The temporary file is always opened with both read and
     * write access.
     */
    static File temp()
    {
        version (Posix)
        {
            /* Implementation note: Since Linux 3.11, there is the flag
             * O_TMPFILE which can be used to open a temporary file. This
             * creates an unnamed inode in the specified directory. Because the
             * inode is unnamed, it will be automatically deleted once the file
             * descriptor is closed. In the future, perhaps 2016, once Linux
             * 3.11 is not so new, this flag should be used instead.
             */

            import core.sys.posix.stdlib : mkstemp;

            // We should be able to rely on /tmp existing. /tmp is usually
            // mounted as a virtual file system that is backed by RAM and should
            // be very fast to access.
            auto name = "/tmp/XXXXXX\0".dup;

            int fd = mkstemp(name.ptr);
            sysEnforce(fd != InvalidHandle, "Failed to create a temporary file");

            // Unlink the file to ensure it is deleted automatically when all
            // file descriptors referring to it are closed.
            sysEnforce(unlink(name.ptr) == 0, "Failed to unlink temporary file");

            return File(fd);
        }
        else version (Windows)
        {
            wchar[MAX_PATH-14] dir;
            sysEnforce(
                GetTempPathW(dir.length, dir.ptr),
                "Failed to get temporary file directory"
                );

            wchar[MAX_PATH] path;
            sysEnforce(
                GetTempFileNameW(dir.ptr, "tmp", 0, path.ptr),
                "Failed to generate temporary file path"
                );

            auto h = .CreateFileW(
                // Temporary file name
                path.ptr,

                // Desired access
                GENERIC_READ | GENERIC_WRITE,

                // Share mode
                FILE_SHARE_DELETE | FILE_SHARE_READ | FILE_SHARE_WRITE,

                // Security attributes
                null,

                // Creation disposition
                CREATE_NEW,

                // Flags and attributes
                FILE_ATTRIBUTE_NORMAL | FILE_ATTRIBUTE_TEMPORARY |
                FILE_FLAG_DELETE_ON_CLOSE,

                // Template file
                null,
            );

            sysEnforce(
                h != InvalidHandle,
                "Failed to create temporary file '"~ name ~"'"
            );

            return File(h);
        }
    }

    ///
    unittest
    {
        auto f = File.temp();
        assert(f.position == 0);
        assert(f.write("Hello") == 5);
        assert(f.position == 5);
    }

    /**
     * Returns the internal file handle.
     */
    @property typeof(_h) handle() pure nothrow
    {
        return _h;
    }

    /**
     * Read data from the file.
     *
     * Params:
     *   buf = The buffer to read the data into. The length of the buffer
     *         specifies how much data should be read.
     *
     * Returns: The number of bytes that were read.
     */
    size_t read(void[] buf)
    in { assert(isOpen); }
    body
    {
        version (Posix)
        {
            immutable n = .read(_h, buf.ptr, buf.length);
            sysEnforce(n != -1);
            return n;
        }
        else version (Windows)
        {
            DWORD n = void;
            sysEnforce(ReadFile(_h, buf.ptr, buf.length, &n, null));
            return n;
        }
    }

    unittest
    {
        auto tf = testFile();

        immutable data = "\r\n\n\r\n";
        file.write(tf.name, data);

        char[data.length] buf;

        auto f = File(tf.name, FileFlags.readExisting);
        assert(buf[0 .. f.read(buf)] == data);
    }

    /**
     * Write data to the file. Returns the number of bytes written (not the
     * number of $(D T)s written).
     *
     * Params:
     *   data = The data to write to the file. The length of the slice indicates
     *          how much data should be written.
     *
     * Returns: The number of bytes that were written.
     */
    size_t write(in void[] data)
    in { assert(isOpen); }
    body
    {
        version (Posix)
        {
            immutable n = .write(_h, data.ptr, data.length);
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
        char[data.length] buf;

        assert(File(tf.name, FileFlags.writeEmpty).write(data) == data.length);
        assert(File(tf.name, FileFlags.readExisting).read(buf));
        assert(buf == data);
    }

    /// An absolute position in the file.
    alias Position = ulong;

    /// An offset from an absolute position
    alias Offset = long;

    /// Special positions.
    static immutable Position
        start = 0,
        end   = Position.max;

    private enum From
    {
        start,
        here,
        end,
    }

    private ulong seek(From from, Offset offset)
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

        auto f = File(tf.name, FileFlags.readWriteAlways);

        immutable data = "abcdefghijklmnopqrstuvwxyz";
        assert(f.write(data) == data.length);

        assert(f.seekTo(f.start, 5) == 5);
        assert(f.skip(5) == 10);
        assert(f.seekTo(f.end, -5) == data.length - 5);

        // Test large offset
        Position p = cast(Offset)int.max * 2;
        assert(f.seekTo(f.start, p) == p);
    }

    /**
     * Seeks relative to the current position
     */
    Position skip(Offset offset)
    {
        return seek(From.here, offset);
    }

    /**
     * Seeks relative to a position.
     *
     * Params:
     *   pos    = Absolute position in the file. $(D File.start) and $(D File.end)
     *            can be used as canonical markers in the file.
     *   offset = Optional offset from the absolute position.
     */
    Position seekTo(Position pos, Offset offset = 0)
    {
        if (pos == end)
            return seek(From.end, offset);
        else
            return seek(From.start, offset + pos);
    }

    /**
     * Gets/sets the current position in the file.
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
     * Gets the size of the file.
     */
    @property Position length()
    in { assert(isOpen); }
    body
    {
        version(Posix)
        {
            // Note that this uses stat to get the length of the file instead of
            // the seek method. This method is safer because it is atomic.
            stat_t stat;
            sysEnforce(.fstat(_h, &stat) != -1);
            return stat.st_size;
        }
        else version (Windows)
        {
            long size = void;
            sysEnforce(GetFileSizeEx(_h, &size));
            return size;
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

    /**
     * Sets the length of the file. This can be used to truncate or extend the
     * length of the file. If the file is extended, the new segment is not
     * guaranteed to be initialized to zeros.
     */
    @property void length(Position len)
    in { assert(isOpen); }
    body
    {
        version (Posix)
        {
            sysEnforce(
                ftruncate(_h, cast(off_t)len) == 0,
                "Failed to set the length of the file"
                );
        }
        else version (Windows)
        {
            // FIXME: This should be atomic.
            // Seek to the position
            auto pos = seekTo(len);
            scope (exit) seekTo(pos);

            sysEnforce(
                SetEndOfFile(_h),
                "Failed to set the length of the file"
                );
        }
    }

    unittest
    {
        auto tf = testFile();
        auto f = File(tf.name, FileFlags.writeEmpty);
        assert(f.length == 0);
        assert(f.position == File.start);

        // Extend
        f.length = 100;
        assert(f.length == 100);
        assert(f.position == File.start);

        // Truncate
        f.length = 0;
        assert(f.length == 0);
        assert(f.position == File.start);
    }

    /**
     * Checks if the file is a terminal.
     */
    @property bool isTerminal()
    in { assert(isOpen); }
    body
    {
        version (Posix)
        {
            return isatty(_h) == 1;
        }
        else version (Windows)
        {
            // TODO: Use GetConsoleMode
            static assert(false, "Implement me!");
        }
    }

    enum LockType
    {
        /**
         * Shared access to the locked file. Other processes can also access the
         * file.
         */
        read,

        /**
         * Exclusive access to the locked file. No other processes may access
         * the file.
         */
        readWrite,
    }

    version (Posix)
    {
        private int lockImpl(int operation, short type,
            Position start, Position length)
        {
            flock fl = {
                l_type:   type,
                l_whence: SEEK_SET,
                l_start:  start,
                l_len:    (length == File.end) ? 0 : length,
                l_pid:    -1,
            };

            return .fcntl(_h, operation, &fl);
        }
    }
    else version (Windows)
    {
        private BOOL lockImpl(alias F, Flags...)(
            Position start, Position length, Flags flags)
        {
            immutable ULARGE_INTEGER
                liStart = {QuadPart: start},
                liLength = {QuadPart: length};

            OVERLAPPED overlapped = {
                Offset: liStart.LowPart,
                OffsetHigh: liStart.HighPart,
                hEvent: null,
            };

            return F(_h, flags, 0, liLength.LowPart, liLength.HighPart,
                &overlapped);
        }
    }

    /**
     * Locks the specified file segment. If the file segment is already locked
     * by another process, waits until the existing lock is released.
     *
     * Note that this is a $(I per-process) lock. This locking mechanism should
     * not be used for multi-threaded synchronization.
     */
    void lock(LockType lockType = LockType.readWrite,
        Position start = File.start, Position length = File.end)
    in { assert(isOpen); }
    body
    {
        version (Posix)
        {
            sysEnforce(
                lockImpl(F_SETLKW,
                    lockType == LockType.readWrite ? F_WRLCK : F_RDLCK,
                    start, length,
                ) != -1, "Failed to lock file"
            );
        }
        else version (Windows)
        {
            sysEnforce(
                lockImpl!LockFileEx(
                    start, length,
                    lockType == LockType.readWrite ? LOCKFILE_EXCLUSIVE_LOCK : 0
                ), "Failed to lock file"
            );
        }
    }

    bool tryLock(LockType lockType = LockType.readWrite,
        Position start = File.start, Offset length = File.end)
    in { assert(isOpen); }
    body
    {
        version (Posix)
        {
            import core.stdc.errno;

            // Set the lock, return immediately if it's being held by another
            // process.
            if (lockImpl(F_SETLK,
                    lockType == LockType.readWrite ? F_WRLCK : F_RDLCK,
                    start, length) != 0
                )
            {
                // Is another process is holding the lock?
                if (errno == EACCES || errno == EAGAIN)
                    return false;
                else
                    sysEnforce(false, "Failed to lock file");
            }

            return true;
        }
        else version (Windows)
        {
            immutable flags = (lockType == LockType.readWrite) ?
                LOCKFILE_EXCLUSIVE_LOCK : 0;
            if (!lockImpl!LockFileEx(start, length,
                    flags | LOCKFILE_FAIL_IMMEDIATELY)
                )
            {
                if (GetLastError() == ERROR_IO_PENDING ||
                    GetLastError() == ERROR_LOCK_VIOLATION)
                    return false;
                else
                    sysEnforce(false, "Failed to lock file");
            }

            return true;
        }
    }

    void unlock(Position start = File.start, Offset length = File.end)
    in { assert(isOpen); }
    body
    {
        version (Posix)
        {
            sysEnforce(
                lockImpl(F_SETLK, F_UNLCK, start, length) != -1,
                "Failed to lock file"
            );
        }
        else version (Windows)
        {
            sysEnforce(lockImpl!UnlockFileEx(start, length),
                    "Failed to unlock file");
        }
    }
}


version (unittest)
{
    /**
     * Generates a file name for testing and attempts to delete it on
     * destruction.
     */
    auto testFile(string file = __FILE__, size_t line = __LINE__)
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
