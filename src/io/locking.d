/**
  Copyright: Copyright Jason White, 2013-
  License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
  Authors:   Jason White
 */
module io.locking;

import io.stream;

/**
  Checks if a type has locking/unlocking methods.
 */
enum isLockingStream(S) =
    is(typeof({
        S s = void;
        s.lock();
        s.unlock();
        bool b = s.tryLock();
    }));

unittest
{
    static assert(!isLockingStream!NullStream);
    static assert( isLockingStream!(LockingStream!NullStream));
}

/**
  Wraps a stream such that it is safe to use across threads.
 */
struct LockingStream(S)
    if (isSource!S || isSink!S)
{
    import core.sync.mutex;

    private
    {
        S _stream;
        Mutex _mutex;
    }

    alias _stream this;

    @disable this(this);

    this(Args...)(auto ref Args args)
        if (is(typeof(S(args))))
    {
        _stream = S(args);
        _mutex = new Mutex;
    }

    /**
      Locks and unlocks the stream for the current scope.
     */
    auto scopeLock()
    {
        static struct ScopeLock
        {
            private LockingStream!S* _s;

            this(LockingStream!S* s)
            {
                _s = s;
                _s.lock();
            }

            ~this()
            {
                _s.unlock();
            }
        }

        return ScopeLock(&this);
    }

    /**
      Locks the stream.
     */
    void lock()
    {
        _mutex.lock();
    }

    /**
      Unlocks the stream.
     */
    void unlock()
    {
        _mutex.unlock();
    }

    /**
      Returns false if the lock is held by another caller. Otherwise, acquires
      the lock and returns true.
     */
    bool tryLock()
    {
        return _mutex.tryLock();
    }

    static if (isSource!S)
    {
        ubyte[] readData(ubyte[] buf)
        {
            auto lock = scopeLock();
            return _stream.readData(buf);
        }
    }

    static if (isSink!S)
    {
        size_t writeData(in ubyte[] data)
        {
            auto lock = scopeLock();
            return _stream.writeData(data);
        }
    }

    static if (isSeekable!S)
    {
        ulong seek(long offset, From from = From.start)
        {
            auto lock = scopeLock();
            return _stream.seek(offset, from);
        }
    }
}
