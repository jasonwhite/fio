/**
 * Copyright: Copyright Jason White, 2014-2016
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.file.temp;

import io.stream;
import io.file.stream;

private version (Windows)
{
    import core.sys.windows.windows;

    extern (Windows) nothrow export
    {
        UINT GetTempFileNameW(
            LPCWSTR lpPathName,
            LPCWSTR lpPrefixString,
            UINT uUnique,
            LPWSTR lpTempFileName
        );

        DWORD GetTempPathW(
            DWORD nBufferLength,
            LPWSTR lpBuffer
        );
    }
}

version (Posix)
private const(char*) tempDirImpl()
{
    import core.sys.posix.stdlib;
    import core.sys.posix.fcntl;

    static const(char*) isDir(const char *path)
    {
        stat_t statbuf = void;

        if (stat(path, &statbuf) == 0 && (statbuf.st_mode & S_IFMT) == S_IFDIR)
            return path;

        return null;
    }

    // TODO: Use secure_getenv, if available, instead?
    if (auto path = getenv("TMPDIR")) return path;
    if (auto path = getenv("TEMP")) return path;
    if (auto path = getenv("TMP")) return path;

    if (auto path = isDir("/tmp")) return path;
    if (auto path = isDir("/var/tmp")) return path;
    if (auto path = isDir("/usr/tmp")) return path;

    return null;
}

version (Windows)
private wstring tempDirImpl()
{
    static wchar[MAX_PATH] buf;
    immutable len = GetTempPathW(buf.length, buf.ptr);
    return cast(wstring)(buf[0 .. len]);
}

/**
 * Returns the path to a directory for temporary files.
 *
 * On Windows, this function returns the result of calling the Windows API
 * function
 * $(LINK2 http://msdn.microsoft.com/en-us/library/windows/desktop/aa364992.aspx, $(D GetTempPath)).
 *
 * On POSIX platforms, it searches through the following list of directories and
 * returns the first one which is found to exist:
 * $(OL
 *     $(LI The directory given by the $(D TMPDIR) environment variable.)
 *     $(LI The directory given by the $(D TEMP) environment variable.)
 *     $(LI The directory given by the $(D TMP) environment variable.)
 *     $(LI $(D /tmp))
 *     $(LI $(D /var/tmp))
 *     $(LI $(D /usr/tmp))
 * )
 *
 * On all platforms, $(D tempDir) returns $(D ".") on failure, representing the
 * current working directory.
 *
 * The return value of the function is cached, so the procedures described above
 * will only be performed the first time the function is called. All subsequent
 * runs will return the same string, regardless of whether environment variables
 * and directory structures have changed in the meantime.
 *
 * The POSIX $(D tempDir) algorithm is inspired by Python's
 * $(LINK2 http://docs.python.org/library/tempfile.html#tempfile.tempdir, $(D tempfile.tempdir)).
 */
T tempDir(T = string)() @trusted
    if (is(T : string) || is(T : wstring))
{
    import std.conv : to;

    static T cache;

    if (cache is null)
    {
        cache = tempDirImpl().to!T();
        if (cache is null) cache = ".";
    }

    return cache;
}

/**
 * Struct representing a temporary file. Returned by $(LREF tempFile).
 */
struct TempFile(File, Path)
{
    /**
     * The opened file stream. If $(D AutoDelete.yes) is specified, when this is
     * closed, the file is deleted.
     */
    File file;

    /**
     * Path to the file. This is not guaranteed to exist if $(D AutoDelete.yes)
     * is specified. For example, on POSIX, the file is deleted as soon as it is
     * created such that, when the last file descriptor to it is closed, the
     * file is deleted. If $(D AutoDelete.no) is specified, this path $(I is)
     * guaranteed to exist.
     */
    Path path;
}

/**
 * Used with $(LREF tempFile) to choose if a temporary file should be deleted
 * automatically when it is closed.
 */
enum AutoDelete
{
    no,
    yes
}

/**
 * Creates a temporary file. The file is automatically deleted when it is no
 * longer referenced. The temporary file is always opened with both read and
 * write access.
 *
 * Params:
 *  autoDelete = If set to $(D AutoDelete.yes) (the default), the file is
 *               deleted from the file system after the file handle is closed.
 *               Otherwise, the file must be deleted manually.
 *  dir = Directory to create the temporary file in. By default, this is $(LREF
 *        tempDir).
 *
 * Example:
 * Creates a temporary file and writes to it.
 * ---
 * auto f = tempFile.file;
 * assert(f.position == 0);
 * f.write("Hello");
 * assert(f.position == 5);
 * ---
 *
 * Example:
 * Creates a temporary file, but doesn't delete it. This is useful to ensure a
 * uniquely named file exists so that it can be written to by another process.
 * ---
 * auto path = tempFile(AutoDelete.no).path;
 * ---
 */
version (Posix)
TempFile!(F, string) tempFile(F = File)(AutoDelete autoDelete = AutoDelete.yes,
        string dir = tempDir)
{
    /* Implementation note: Since Linux 3.11, there is the flag O_TMPFILE which
     * can be used to open a temporary file. This creates an unnamed inode in
     * the specified directory. Because the inode is unnamed, it will be
     * automatically deleted once the file descriptor is closed. In the future,
     * once Linux 3.11 is not so new, this flag could be used instead.
     */

    import core.sys.posix.stdlib : mkstemp;
    import core.sys.posix.unistd : unlink;
    import std.exception : assumeUnique;

    char[] path = dir ~ "/XXXXXX\0".dup;

    int fd = mkstemp(path.ptr);
    sysEnforce(fd != File.InvalidHandle,
        "Failed to create temporary file '"~ path[0 .. $-1].idup ~"'"
        );

    // Unlink the file to ensure it is deleted automatically when all
    // file descriptors referring to it are closed.
    if (autoDelete == AutoDelete.yes)
        sysEnforce(unlink(path.ptr) == 0, "Failed to unlink temporary file");

    static if (is(F == class))
        return typeof(return)(new F(fd), assumeUnique(path[0 .. $-1]));
    else
        return typeof(return)(F(fd), assumeUnique(path[0 .. $-1]));
}

version (Windows)
TempFile!(F, T) tempFile(F = File, T = string)(
        AutoDelete autoDelete = AutoDelete.yes, T dir = tempDir!T)
    if ((is(T : string) || is(T : wstring)))
{
    import std.conv : to;
    import std.utf : toUTF16z;
    import std.exception : assumeUnique;
    import core.stdc.wchar_ : wcslen;

    wchar[MAX_PATH] buf;
    sysEnforce(
        GetTempFileNameW(toUTF16z(dir), "tmp", 0, buf.ptr),
        "Failed to generate temporary file path"
        );

    wchar[] path = buf[0 .. wcslen(buf.ptr)];

    auto h = CreateFileW(
        // Temporary file name
        path.ptr,

        // Desired access
        GENERIC_READ | GENERIC_WRITE,

        // Share mode
        FILE_SHARE_DELETE | FILE_SHARE_READ | FILE_SHARE_WRITE,

        // Security attributes
        null,

        // Creation disposition. Note that GetTempFileName creates this file.
        CREATE_ALWAYS,

        // Flags and attributes
        FILE_ATTRIBUTE_NORMAL | FILE_ATTRIBUTE_TEMPORARY |
        ((autoDelete == AutoDelete.yes) ? FILE_FLAG_DELETE_ON_CLOSE : 0),

        // Template file
        null,
    );

    sysEnforce(
        h != File.InvalidHandle,
        "Failed to create temporary file '"~ path.to!string ~"'"
    );

    static if (is(F == class))
        return TempFile(new F(h), assumeUnique(path));
    else
        return TempFile(F(h), assumeUnique(path));
}

unittest
{
    auto f = tempFile.file;
    assert(f.position == 0);
    f.write("Hello");
    assert(f.position == 5);
}
