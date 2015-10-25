/**
 * Copyright: Copyright Jason White, 2015
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
 * Returns a cached path to the temporary directory.
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

struct TempFile(File, Path)
{
    File file;
    Path path;
}

/**
 * Creates a temporary file. The file is automatically deleted when it is no
 * longer referenced. The temporary file is always opened with both read and
 * write access.
 */
version (Posix)
TempFile!(F, string) tempFile(F = File)(string dir = tempDir, bool autoDelete = true)
{
    /* Implementation note: Since Linux 3.11, there is the flag
     * O_TMPFILE which can be used to open a temporary file. This
     * creates an unnamed inode in the specified directory. Because the
     * inode is unnamed, it will be automatically deleted once the file
     * descriptor is closed. In the future, perhaps 2016, once Linux
     * 3.11 is not so new, this flag should be used instead.
     */

    import core.sys.posix.stdlib : mkstemp;
    import core.sys.posix.unistd : unlink;
    import std.exception : assumeUnique;

    char[] path = dir ~ "/XXXXXX\0".dup;

    int fd = mkstemp(path.ptr);
    sysEnforce(fd != File.InvalidHandle,
        "Failed to create temporary file '"~ path.idup ~"'"
        );

    // Unlink the file to ensure it is deleted automatically when all
    // file descriptors referring to it are closed.
    if (autoDelete)
        sysEnforce(unlink(path.ptr) == 0, "Failed to unlink temporary file");

    static if (is(F == class))
        return typeof(return)(new F(fd), assumeUnique(path));
    else
        return typeof(return)(F(fd), assumeUnique(path));
}

version (Windows)
TempFile!(F, T) tempFile(F = File, T = string)(T dir = tempDir!T, bool autoDelete = true)
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

    // FIXME: Not very elegant. There is no wchar* overload for fromStringz.
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
        (autoDelete ? FILE_FLAG_DELETE_ON_CLOSE : 0),

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

///
unittest
{
    auto f = tempFile.file;
    assert(f.position == 0);
    assert(f.write("Hello") == 5);
    assert(f.position == 5);
}

