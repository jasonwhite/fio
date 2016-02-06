[buildbadge]: https://travis-ci.org/jasonwhite/io.svg?branch=master
[buildstatus]: https://travis-ci.org/jasonwhite/io

# IO Streams [![Build Status][buildbadge]][buildstatus]

*This is a work in progress.*

This is an IO stream library for D. The primary purpose of this package is to
provide a better API than what is currently available in the D standard library.
Secondly, it is meant to be fast. All file operations are implemented using the
low-level system calls provided by the operating system.

The goal is to eventually replace the disparate IO modules in [Phobos][] with
this package. Currently, these include [`std.stdio`][std.stdio],
[`std.mmfile`][std.mmfile], [`std.stream`][std.stream], and
[`std.cstream`][std.cstream].

[Phobos]: http://dlang.org/phobos/
[std.stdio]: http://dlang.org/phobos/std_stdio.html
[std.mmfile]: http://dlang.org/phobos/std_mmfile.html
[std.stream]: http://dlang.org/phobos/std_stream.html
[std.cstream]: http://dlang.org/phobos/std_cstream.html

## Features

 * File streams
 * Memory mapped files
 * Pipes
 * Temporary files
 * Generic stream buffering
 * Text serialization to streams

## License

[Boost license](/LICENSE.md)
