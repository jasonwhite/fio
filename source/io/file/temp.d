/**
 * Copyright: Copyright Jason White, 2014
 * License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Jason White
 */
module io.file.temp;

import io.stream;
import io.file.stream;


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

    // TODO: Use secure_getenv instead if available?
    if (auto path = getenv("TMPDIR")) return path;
    if (auto path = getenv("TEMP")) return path;
    if (auto path = getenv("TMP")) return path;

    if (auto path = isDir("/tmp")) return path;
    if (auto path = isDir("/var/tmp")) return path;
    if (auto path = isDir("/usr/tmp")) return path;

    return null;
}

version (Windows)
private const(wchar[]) tempDirImpl()
{
    import core.sys.windows.windows : WCHAR, MAX_PATH, GetTempPathW;

    static WCHAR[MAX_PATH] buf;
    DWORD len = GetTempPathW(buf.length, buf.ptr);
    return buf[0 .. len];
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


/**
 * Creates a temporary file. The file is automatically deleted when it is no
 * longer referenced. The temporary file is always opened with both read and
 * write access.
 */
version (Posix)
File tempFile(string dir = tempDir)
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

    char[] path = dir ~ "/XXXXXX\0".dup;

    int fd = mkstemp(path.ptr);
    sysEnforce(fd != File.InvalidHandle,
        "Failed to create temporary file '"~ path.idup ~"'"
        );

    // Unlink the file to ensure it is deleted automatically when all
    // file descriptors referring to it are closed.
    sysEnforce(unlink(path.ptr) == 0, "Failed to unlink temporary file");

    return File(fd);
}

version (Windows)
File tempFile(T)(T dir = tempDir!T)
    if (is(T : string) || is(T : wstring))
{
    import core.sys.windows.windows;
    import std.conv : to;

    auto d = dir.to!wstring ~ '\0';

    wchar[MAX_PATH] path;
    sysEnforce(
        GetTempFileNameW(d.ptr, "tmp", 0, path.ptr),
        "Failed to generate temporary file path"
        );

    auto h = CreateFileW(
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
        h != File.InvalidHandle,
        "Failed to create temporary file '"~ path ~"'"
    );

    return File(h);
}

///
unittest
{
    auto f = tempFile();
    assert(f.position == 0);
    assert(f.write("Hello") == 5);
    assert(f.position == 5);
}

