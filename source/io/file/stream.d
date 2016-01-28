/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 *
 * Description:
 * This module provides a low-level file stream class.
 *
 * Synopsis:
 * ---
 * // Open a new file in read/write mode. Throws an exception if the file exists.
 * auto f = File("myfile", FileFlags.readWriteNew);
 *
 * // Write an arbitrary array to the stream.
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
    import core.sys.posix.sys.uio;
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

        BOOL FlushFileBuffers(HANDLE hFile);
        BOOL GetFileSizeEx(HANDLE hFile, long* lpFileSize);
        DWORD GetFileType(HANDLE hFile);

        enum
        {
            FILE_TYPE_UNKNOWN = 0x0000,
            FILE_TYPE_DISK    = 0x0001,
            FILE_TYPE_CHAR    = 0x0002,
            FILE_TYPE_PIPE    = 0x0003,
            FILE_TYPE_REMOTE  = 0x8000,
        }

        enum
        {
            DUPLICATE_CLOSE_SOURCE = 0x00000001,
            DUPLICATE_SAME_ACCESS  = 0x00000002,
        }
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
struct FileBase
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

    // Name of the file, for debugging purposes only.
    debug string name;

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
        debug this.name = name;

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
     * Takes control of a file handle.
     *
     * It is assumed that we have exclusive control over the file handle and will
     * be closed upon destruction as usual. If non-exclusive control is desired,
     * use $(D dup) instead.
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

    /**
     * Duplicates the given platform-specific file handle. This is useful for
     * taking non-exclusive control over a file handle.
     */
    static F dup(F = File)(Handle h)
    {
        version (Posix)
        {
            immutable new_h = .dup(h);
            sysEnforce(new_h != InvalidHandle, "Failed to duplicate handle");
            return F(new_h);
        }
        else version (Windows)
        {
            Handle new_h = void;
            auto proc = GetCurrentProcess();
            auto ret = DuplicateHandle(
                proc,   // Process with the file handle
                h,      // Handle to duplicate
                proc,   // Process for the duplicated handle
                &new_h, // The duplicated handle
                0,      // Access flags, ignored
                true,   // Allow this handle to be inherited
                DUPLICATE_SAME_ACCESS
            );
            sysEnforce(ret, "Failed to duplicate handle");
            return F(new_h);
        }
    }

    /**
     * Copying is disabled because references counting should be used instead.
     */
    @disable this(this);

    /**
     * Closes the stream if it is open. Otherwise, it does nothing.
     */
    void close()
    {
        // The file handle should only be invalid if the constructor throws an
        // exception.
        if (!isOpen) return;

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
     * Returns the internal file handle. On POSIX, this is a file descriptor. On
     * Windows, this is an object handle.
     */
    @property Handle handle() pure nothrow
    {
        return _h;
    }

    /**
     * Returns true if the file is open.
     */
    @property bool isOpen()
    {
        return _h != InvalidHandle;
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
    in { assert(isOpen); }
    body
    {
        version (Posix)
        {
            immutable n = .read(_h, buf.ptr, buf.length);
            sysEnforce(n >= 0, "Failed to read from file");
            return n;
        }
        else version (Windows)
        {
            DWORD n = void;
            sysEnforce(
                ReadFile(_h, buf.ptr, buf.length, &n, null),
                "Failed to read from file"
                );
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

    version (Posix) private size_t readv(iovec* iov, ubyte[][] bufs)
    {
        for (size_t i = 0; i < bufs.length; ++i)
        {
            iov[i].iov_base = cast(void*)bufs[i].ptr;
            iov[i].iov_len  = bufs[i].length;
        }

        immutable n = .readv(_h, iov, cast(int)bufs.length);
        sysEnforce(n != -1, "Failed to read from file");
        return n;
    }

    /**
     * Vectorized read.
     *
     * Params:
     *   bufs = The buffers to read the data into. The length of each buffer
     *          specifies how much data should be read.
     *
     * Returns: The number of bytes that were read. 0 indicates that the end of
     * the file has been reached.
     */
    size_t readv(size_t StackSize = 32)(ubyte[][] bufs...)
    {
        import core.stdc.stdlib : malloc, free;

        version (Posix)
        {
            if (bufs.length <= StackSize)
            {
                iovec[StackSize] iov = void;
                return readv(iov.ptr, bufs);
            }
            else
            {
                // Not enough space in stack-allocated buffer, fallback to using
                // a heap-allocated buffer.
                iovec* iov = cast(iovec*)malloc(iovec.sizeof * bufs.length);
                scope (exit) free(iov);
                return readv(iov, bufs);
            }
        }
        else version (Windows)
        {
            // TODO: Use ReadFileScatter
            static assert(false, "Implement me.");
        }
    }

    unittest
    {
        auto tf = testFile();

        immutable ubyte[] data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

        ubyte[4] buf1;
        ubyte[3] buf2;
        ubyte[5] buf3;

        static assert(buf1.length + buf2.length + buf3.length == data.length);

        assert(File(tf.name, FileFlags.writeEmpty).write(data) == data.length);
        assert(File(tf.name, FileFlags.readExisting).readv(buf1, buf2, buf3) == data.length);
        assert(buf1 ~ buf2 ~ buf3 == data);

        assert(File(tf.name, FileFlags.writeEmpty).write(data) == data.length);
        assert(File(tf.name, FileFlags.readExisting).readv!2(buf1, buf2, buf3) == data.length);
        assert(buf1 ~ buf2 ~ buf3 == data);
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
    in { assert(isOpen); }
    body
    {
        version (Posix)
        {
            immutable n = .write(_h, data.ptr, data.length);
            sysEnforce(n != -1, "Failed to write to file");
            return n;
        }
        else version (Windows)
        {
            DWORD written = void;
            sysEnforce(
                WriteFile(_h, data.ptr, data.length, &written, null),
                "Failed to write to file"
                );
            return written;
        }
    }

    alias put = write;

    unittest
    {
        auto tf = testFile();

        immutable data = "\r\n\n\r\n";
        char[data.length] buf;

        assert(File(tf.name, FileFlags.writeEmpty).write(data) == data.length);
        assert(File(tf.name, FileFlags.readExisting).read(buf));
        assert(buf == data);
    }

    version (Posix) private size_t writev(iovec* iov, in ubyte[][] bufs)
    {
        for (size_t i = 0; i < bufs.length; ++i)
        {
            iov[i].iov_base = cast(void*)bufs[i].ptr;
            iov[i].iov_len  = bufs[i].length;
        }

        immutable n = .writev(_h, iov, cast(int)bufs.length);
        sysEnforce(n != -1, "Failed to write to file");
        return n;
    }

    /**
     * Vectorized write.
     *
     * Params:
     *   bufs = The buffers to write the data from. The length of each buffer
     *          specifies how much data should be written.
     *
     * Returns: The number of bytes that were written.
     */
    size_t writev(size_t StackSize = 32)(in ubyte[][] bufs...)
    {
        import core.stdc.stdlib : malloc, free;

        version (Posix)
        {
            if (bufs.length <= StackSize)
            {
                iovec[StackSize] iov = void;
                return writev(iov.ptr, bufs);
            }
            else
            {
                // Not enough space in stack-allocated buffer, fallback to using
                // a heap-allocated buffer.
                iovec* iov = cast(iovec*)malloc(iovec.sizeof * bufs.length);
                scope (exit) free(iov);
                return writev(iov, bufs);
            }
        }
        else version (Windows)
        {
            // TODO: Use WriteFileGather
            static assert(false, "Implement me.");
        }
    }

    unittest
    {
        auto tf = testFile();

        immutable ubyte[] data1 = [1, 2, 3, 4, 5, 6, 7, 8];
        immutable ubyte[] data2 = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];
        immutable ubyte[] data3 = [21, 22, 23, 24];
        immutable totalLength = data1.length + data2.length + data3.length;
        ubyte[totalLength] buf;

        assert(File(tf.name, FileFlags.writeEmpty).writev(data1, data2, data3) == totalLength);
        assert(File(tf.name, FileFlags.readExisting).read(buf) == buf.length);
        assert(buf == data1 ~ data2 ~ data3);

        assert(File(tf.name, FileFlags.writeEmpty).writev!2(data1, data2, data3) == totalLength);
        assert(File(tf.name, FileFlags.readExisting).read(buf) == buf.length);
        assert(buf == data1 ~ data2 ~ data3);
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

    unittest
    {
        auto tf = testFile();

        auto f = File(tf.name, FileFlags.readWriteAlways);

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
    in { assert(isOpen); }
    body
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
    @property void length(Offset len)
    in { assert(isOpen); }
    body
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
            // FIXME: This is not thread safe because it requires 4 system calls.
            auto pos = seekTo(0, From.here);
            seekTo(len); // Seek to the correct position
            scope (exit) seekTo(pos); // Seek back

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
    in { assert(isOpen); }
    body
    {
        version (Posix)
        {
            return isatty(_h) == 1;
        }
        else version (Windows)
        {
            return GetFileType(_h) == FILE_TYPE_CHAR;
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

    /**
     * Like $(D lock), but returns false immediately if the lock is held by
     * another process. Returns true if the specified region in the file was
     * successfully locked.
     */
    bool tryLock(LockType lockType = LockType.readWrite,
        Offset start = 0, Offset length = Offset.max)
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

    void unlock(Offset start = 0, Offset length = Offset.max)
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

    /**
     * Syncs all modified cached data of the file to disk. This includes data
     * written to the file as well as meta data (e.g., last modified time, last
     * access time).
     */
    void sync()
    in { assert(isOpen); }
    body
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

    /**
     * Copies the rest of this file to the other. The positions of both files
     * are appropriately incremented, as if one called read()/write() to copy
     * the file. The number of copied bytes is returned.
     */
    version (linux)
    {
        size_t copyTo(File other, size_t n = ptrdiff_t.max)
        in { assert(isOpen && other.isOpen); }
        body
        {
            immutable written = .sendfile(other._h, _h, null, n);
            sysEnforce(written >= 0, "Failed to copy file.");
            return written;
        }

        unittest
        {
            import std.conv : to;

            auto a = tempFile.file;
            auto b = tempFile.file;
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

unittest
{
    import io.stream.types;
    static assert(isSink!FileBase);
    static assert(isSource!FileBase);
    static assert(isSeekable!FileBase);
}

import std.typecons;
import io.buffer.fixed;
alias UnbufferedFile = RefCounted!(FileBase, RefCountedAutoInitialize.no);
alias File = FixedBuffer!UnbufferedFile;

unittest
{
    import io.stream.types;
    import io.buffer.traits;

    static assert(isSink!UnbufferedFile);
    static assert(isSource!UnbufferedFile);
    static assert(isSeekable!UnbufferedFile);
    static assert(isBufferable!UnbufferedFile);

    static assert(isSink!File);
    static assert(isSource!File);
    static assert(isSeekable!File);
    static assert(isFlushable!File);
}

unittest
{
    auto tf = testFile();

    immutable message = "The quick brown fox jumps over the lazy dog.";

    char[message.length] buf;

    foreach (bufSize; [0, 1, 2, 8, 16, 64, 256])
    {
        {
            auto f = File(tf.name, FileFlags.writeEmpty);
            f.bufferSize = bufSize;
            assert(f.bufferSize == bufSize);
            assert(f.write(message) == message.length);
        }

        {
            auto f = File(tf.name, FileFlags.readExisting);
            f.bufferSize = bufSize;
            assert(f.bufferSize == bufSize);
            assert(buf[0 .. f.read(buf)] == message);
        }
    }
}

unittest
{
    auto tf = testFile();

    immutable data = "The quick brown fox jumps over the lazy dog.";
    char[data.length] buffer;

    foreach (bufSize; [0, 1, 2, 8, 16, 64, 4096, 8192])
    {
        auto f = File(tf.name, FileFlags.readWriteEmpty);
        f.bufferSize = bufSize;
        assert(f.bufferSize == bufSize);

        assert(f.write(data) == data.length);
        f.position = 0;
        assert(f.read(buffer) == buffer.length);
        assert(buffer == data);
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
