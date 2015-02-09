/**
 * Copyright: Copyright Jason White, 2015
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 *
 * Description:
 * This module provides a low-level file stream class.
 *
 * Synopsis:
 * ---
 * // Open a new file in read/write mode. Throws an exception if the file exists.
 * auto f = new File("myfile", FileFlags.readWriteNew);
 *
 * // Write an arbitrary arrays to the stream.
 * f.write("Hello world!");
 *
 * // Seek to the beginning.
 * f.position = 0;
 *
 * // Read in 5 bytes.
 * char buf[5];
 * f.read(buf);
 * assert(buf == "Hello");
 * ---
 * Note that the file handle is closed when garbage is collected. For design
 * simplicity, there is no $(D close()) function. If deterministic destruction
 * is required, use $(D scoped!File).
 */
module io.file.stream;

import io.stream;
public import io.file.flags;

version (unittest)
{
    import file = std.file; // For easy file creation/deletion.
    import io.file.temp;
}

version (Posix)
{
    import core.sys.posix.fcntl;
    import core.sys.posix.unistd;
    import std.exception : ErrnoException;

    version (linux)
    {
        extern (C): @system: nothrow:
        ssize_t sendfile(int out_fd, int in_fd, off_t *offset, size_t count);
    }

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
 * A cross-platform wrapper around low-level file operations.
 */
class File : Seekable!SourceSink
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
     * // file already exists. The file is automatically closed when it falls
     * // out of scope.
     * auto f = File("filename", FileFlags.writeNew);
     * f.write("Hello world!");
     * ---
     */
    this(string name, FileFlags flags = FileFlags.readExisting)
    {
        version (Posix)
        {
            import std.string : toStringz;

            _h = .open(toStringz(name), flags, 0b110_000_000);
        }
        else version (Windows)
        {
            import std.utf : toUTF16z;

            _h = .CreateFileW(
                name.toUTF16z(),       // File name
                flags.access,          // Desired access
                flags.share,           // Share mode
                null,                  // Security attributes
                flags.mode,            // Creation disposition
                FILE_ATTRIBUTE_NORMAL, // Flags and attributes
                null,                  // Template file handle
                );
        }

        sysEnforce(_h != InvalidHandle, "Failed to open file '"~ name ~"'");
    }

    /// Ditto
    this(string name, FileFlags flags = FileFlags.readExisting) shared
    {
        version (Posix)
        {
            import std.string : toStringz;

            _h = .open(toStringz(name), flags, 0b110_000_000);
        }
        else version (Windows)
        {
            import std.utf : toUTF16z;

            _h = .CreateFileW(
                name.toUTF16z(),       // File name
                flags.access,          // Desired access
                flags.share,           // Share mode
                null,                  // Security attributes
                flags.mode,            // Creation disposition
                FILE_ATTRIBUTE_NORMAL, // Flags and attributes
                null,                  // Template file handle
                );
        }

        sysEnforce(_h != InvalidHandle, "Failed to open file '"~ name ~"'");
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

        assert( new File(tf.name, FileFlags.readExisting).ce);
        assert( new File(tf.name, FileFlags.writeExisting).ce);
        assert(!new File(tf.name, FileFlags.writeNew).ce);
        assert(!new File(tf.name, FileFlags.writeAlways).ce);

        // Make sure the file *does* exist.
        .file.write(tf.name, data);

        assert(!new File(tf.name, FileFlags.readExisting).ce);
        assert(!new File(tf.name, FileFlags.writeExisting).ce);
        assert( new File(tf.name, FileFlags.writeNew).ce);
        assert(!new File(tf.name, FileFlags.writeAlways).ce);
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
     *     The file must be opened with special flags that cannot be obtained
     *     via $(D FileFlags)
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

    /// Ditto
    this(Handle h) shared
    {
        _h = h;
    }

    /**
     * Duplicates the internal file handle and returns a new file object.
     */
    typeof(this) dup()
    {
        version (Posix)
        {
            immutable h = .dup(_h);
            sysEnforce(h != InvalidHandle, "Failed to duplicate handle");
            return new File(h);
        }
        else version (Windows)
        {
            immutable proc = GetCurrentProcess();
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
            return new File(ret);
        }
    }

    /// Ditto
    typeof(this) dup() shared
    {
        return (cast(File)this).dup();
    }

    unittest
    {
        auto tf = testFile();

        auto a = new File(tf.name, FileFlags.writeEmpty);

        auto b = a.dup; // Copy
        b.write("abcd");

        assert(a.position == 4);
    }

    /// Ditto
    ~this()
    {
        // The file handle should only be invalid if the constructor throws an
        // exception.
        if (_h == InvalidHandle) return;

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
     * Returns the internal file handle. On POSIX, this is a file descriptor. On
     * Windows, this is an object handle.
     */
    @property Handle handle() const pure nothrow
    {
        return _h;
    }

    /// Ditto
    @property Handle handle() shared const pure nothrow
    {
        return (cast(File)this).handle();
    }

    /**
     * Reads data from the file.
     *
     * Params:
     *   buf = The buffer to read the data into. The length of the buffer
     *         specifies how much data should be read.
     *
     * Returns: The number of bytes that were read. 0 indicates that the end of
     * the file has been reached.
     */
    size_t read(void[] buf)
    {
        version (Posix)
        {
            immutable n = .read(_h, buf.ptr, buf.length);
            sysEnforce(n >= 0);
            return n;
        }
        else version (Windows)
        {
            DWORD n = void;
            sysEnforce(ReadFile(_h, buf.ptr, buf.length, &n, null));
            return n;
        }
    }

    /// Ditto
    size_t read(void[] buf) shared
    {
        // The underlying operation should already be atomic under the hood.
        // Thus, there is no need for synchronization here.
        return (cast(File)this).read(buf);
    }

    unittest
    {
        auto tf = testFile();

        immutable data = "\r\n\n\r\n";
        file.write(tf.name, data);

        char[data.length] buf;

        auto f = new File(tf.name, FileFlags.readExisting);
        assert(buf[0 .. f.read(buf)] == data);
    }

    /**
     * Writes data to the file.
     *
     * Params:
     *   data = The data to write to the file. The length of the slice indicates
     *          how much data should be written.
     *
     * Returns: The number of bytes that were written.
     */
    size_t write(const(void)[] data)
    {
        version (Posix)
        {
            immutable n = .write(_h, data.ptr, data.length);
            sysEnforce(n != -1);
            return n;
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

    /// Ditto
    size_t write(const(void)[] data) shared
    {
        // The underlying operation should already be atomic under the hood.
        // Thus, there is no need for synchronization here.
        return (cast(File)this).write(data);
    }

    unittest
    {
        auto tf = testFile();

        immutable data = "\r\n\n\r\n";
        char[data.length] buf;

        assert(new File(tf.name, FileFlags.writeEmpty).write(data) == data.length);
        assert(new File(tf.name, FileFlags.readExisting).read(buf));
        assert(buf == data);
    }

    /// An offset from an absolute position
    alias Offset = long;

    /**
     * Seeks relative to a position.
     *
     * Params:
     *   offset = Offset relative to a reference point.
     *   from   = Optional reference point.
     */
    Offset seekTo(Offset offset, From from = From.start)
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

            immutable pos = .lseek(_h, offset, whence);
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

            Offset pos = void;
            sysEnforce(SetFilePointerEx(_h, offset, &pos, whence),
                "Failed to seek to position");
            return pos;
        }
    }

    /// Ditto
    Offset seekTo(Offset offset, From from = From.start) shared
    {
        // The underlying operation should already be atomic under the hood.
        // Thus, there is no need for synchronization here.
        return (cast(File)this).seekTo(offset, from);
    }

    unittest
    {
        auto tf = testFile();

        auto f = new File(tf.name, FileFlags.readWriteAlways);

        immutable data = "abcdefghijklmnopqrstuvwxyz";
        assert(f.write(data) == data.length);

        assert(f.seekTo(5) == 5);
        assert(f.skip(5) == 10);
        assert(f.seekTo(-5, From.end) == data.length - 5);

        // Test large offset
        assert(f.seekTo(Offset.max) == Offset.max);
    }

    /**
     * Gets the size of the file.
     */
    @property Offset length()
    {
        version(Posix)
        {
            // Note that this uses stat to get the length of the file instead of
            // the seek method. This method is safer because it is atomic.
            stat_t stat = void;
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

    /// Ditto
    @property Offset length() shared
    {
        // The underlying operation should already be atomic under the hood.
        // Thus, there is no need for synchronization here.
        return (cast(File)this).length();
    }

    unittest
    {
        auto tf = testFile();
        auto f = new File(tf.name, FileFlags.writeEmpty);

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
    @property void length(Offset len)
    {
        version (Posix)
        {
            sysEnforce(
                ftruncate(_h, len) == 0,
                "Failed to set the length of the file"
                );
        }
        else version (Windows)
        {
            // FIXME: Is this thread-safe?
            auto pos = seekTo(len);   // Seek to the correct position
            scope (exit) seekTo(pos); // Seek back

            sysEnforce(
                SetEndOfFile(_h),
                "Failed to set the length of the file"
                );
        }
    }

    /// Ditto
    version (Posix)
    @property void length(Offset len) shared
    {
        // The underlying operation should already be atomic under the hood.
        // Thus, there is no need for synchronization here.
        (cast(File)this).length(len);
    }

    /// Ditto
    version (Windows)
    synchronized @property void length(Offset len) shared
    {
        // On Windows, the underlying operation involves a seek, which is not
        // atomic. Thus, this method must be synchronized.
        (cast(File)this).length(len);
    }

    unittest
    {
        auto tf = testFile();
        auto f = new File(tf.name, FileFlags.writeEmpty);
        assert(f.length == 0);
        assert(f.position == 0);

        // Extend
        f.length = 100;
        assert(f.length == 100);
        assert(f.position == 0);

        // Truncate
        f.length = 0;
        assert(f.length == 0);
        assert(f.position == 0);
    }

    /**
     * Checks if the file is a terminal.
     */
    @property bool isTerminal()
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

    /// Ditto
    @property bool isTerminal() shared
    {
        // The underlying operation should already be atomic under the hood.
        // Thus, there is no need for synchronization here.
        return (cast(File)this).isTerminal();
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
            Offset start, Offset length)
        {
            flock fl = {
                l_type:   type,
                l_whence: SEEK_SET,
                l_start:  start,
                l_len:    (length == Offset.max) ? 0 : length,
                l_pid:    -1,
            };

            return .fcntl(_h, operation, &fl);
        }

        /// Ditto
        private int lockImpl(int operation, short type,
            Offset start, Offset length) shared
        {
            // The underlying operation should already be atomic under the hood.
            // Thus, there is no need for synchronization here.
            return (cast(File)this).lockImpl(operation, type, start, length);
        }
    }
    else version (Windows)
    {
        private BOOL lockImpl(alias F, Flags...)(
            Offset start, Offset length, Flags flags)
        {
            import std.conv : to;

            immutable ULARGE_INTEGER
                liStart = {QuadPart: start.to!ulong},
                liLength = {QuadPart: length.to!ulong};

            OVERLAPPED overlapped = {
                Offset: liStart.LowPart,
                OffsetHigh: liStart.HighPart,
                hEvent: null,
            };

            return F(_h, flags, 0, liLength.LowPart, liLength.HighPart,
                &overlapped);
        }

        /// Ditto
        private BOOL lockImpl(alias F, Flags...)(
            Offset start, Offset length, Flags flags) shared
        {
            // The underlying operation should already be atomic under the hood.
            // Thus, there is no need for synchronization here.
            return (cast(File)this).lockImpl!(F, Flags)(start, length, flags);
        }
    }

    /**
     * Locks the specified file segment. If the file segment is already locked
     * by another process, waits until the existing lock is released.
     *
     * Note that this is a $(I per-process) lock. This locking mechanism should
     * not be used for thread-level synchronization. For that, use the $(D
     * synchronized) statement.
     */
    void lock(LockType lockType = LockType.readWrite,
        Offset start = 0, Offset length = Offset.max)
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

    /// Ditto
    void lock(LockType lockType = LockType.readWrite,
        Offset start = 0, Offset length = Offset.max) shared
    {
        // The underlying operation should already be atomic under the hood.
        // Thus, there is no need for synchronization here.
        (cast(File)this).lock(lockType, start, length);
    }

    /**
     * Like $(D lock), but returns false immediately if the lock is held by
     * another process. Returns true if the specified region in the file was
     * successfully locked.
     */
    bool tryLock(LockType lockType = LockType.readWrite,
        Offset start = 0, Offset length = Offset.max)
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
            immutable flags = LOCKFILE_FAIL_IMMEDIATELY | (
                (lockType == LockType.readWrite) ? LOCKFILE_EXCLUSIVE_LOCK : 0);
            if (!lockImpl!LockFileEx(start, length, flags))
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

    /// Ditto
    bool tryLock(LockType lockType = LockType.readWrite,
        Offset start = 0, Offset length = Offset.max) shared
    {
        // The underlying operation should already be atomic under the hood.
        // Thus, there is no need for synchronization here.
        return (cast(File)this).tryLock(lockType, start, length);
    }

    void unlock(Offset start = 0, Offset length = Offset.max)
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

    /// Ditto
    void unlock(Offset start = 0, Offset length = Offset.max) shared
    {
        // The underlying operation should already be atomic under the hood.
        // Thus, there is no need for synchronization here.
        return (cast(File)this).unlock(start, length);
    }

    /**
     * Syncs all modified cached data of the file to disk. This includes data
     * written to the file as well as meta data (e.g., last modified time, last
     * access time).
     */
    void sync()
    {
        version (Posix)
        {
            sysEnforce(fsync(_h) == 0);
        }
        else version (Windows)
        {
            sysEnforce(FlushFileBuffers(_h) != 0);
        }
    }

    /// Ditto
    void sync() shared
    {
        // The underlying operation should already be atomic under the hood.
        // Thus, there is no need for synchronization here.
        (cast(File)this).sync();
    }

    /**
     * Like $(D sync()), but does not flush meta data.
     *
     * NOTE: On Windows, this is exactly the same as $(D sync()).
     */
    void syncData()
    {
        version (Posix)
        {
            sysEnforce(fdatasync(_h) == 0);
        }
        else version (Windows)
        {
            sysEnforce(FlushFileBuffers(_h) != 0);
        }
    }

    /// Ditto
    void syncData() shared
    {
        // The underlying operation should already be atomic under the hood.
        // Thus, there is no need for synchronization here.
        (cast(File)this).syncData();
    }

    /**
     * Copies the rest of this file to the other. The positions of both files
     * are appropriately incremented, as if one called read()/write() to copy
     * the file. The number of copied bytes is returned.
     */
    version (linux)
    {
        size_t copyTo(File other, size_t n = ptrdiff_t.max)
        {
            immutable written = .sendfile(other._h, _h, null, n);
            sysEnforce(written >= 0, "Failed to copy file.");
            return written;
        }

        /// Ditto
        size_t copyTo(File other, size_t n = ptrdiff_t.max) shared
        {
            // The underlying operation should already be atomic under the hood.
            // Thus, there is no need for synchronization here.
            return (cast(File)this).copyTo(other, n);
        }

        /// Ditto
        size_t copyTo(shared(File) other, size_t n = ptrdiff_t.max) shared
        {
            // The underlying operation should already be atomic under the hood.
            // Thus, there is no need for synchronization here.
            return (cast(File)this).copyTo(cast(File)other, n);
        }

        unittest
        {
            import std.conv : to;

            auto a = tempFile();
            auto b = tempFile();
            immutable s = "This will be copied to the other file.";
            a.write(s);
            a.position = 0;
            a.copyTo(b);
            assert(a.position == s.length);

            b.position = 0;

            char[s.length] buf;
            assert(b.read(buf) == s.length);
            assert(buf == s);
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
