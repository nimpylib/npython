
const
  Py_UNLOCKED* = 0u8
  Py_LOCKED* = 1u8

#XXX: std/locks lacks isLocked

import ./pyatomic
export SingleThread

type
  PyMutex*{.pure.} = object
    bits: uint8
  
using m: var PyMutex
{.push inline.}
proc lock*(m) =
  ## `PyMutex_Lock`
  ## 
  ## Locks the mutex.
  ## 
  ## If the mutex is currently locked, the calling thread will be parked until
  ## the mutex is unlocked.
  let expected = Py_UNLOCKED
  if not Py_atomic_compare_exchange(m.bits.addr, expected.addr, Py_LOCKED):
    m.lock()


proc unlock*(m) =
  let expected = Py_LOCKED
  if not Py_atomic_compare_exchange(m.bits.addr, expected.addr, Py_UNLOCKED):
    m.unlock()

proc isLocked*(m): bool =
  (Py_atomic_load(m.bits.addr) and Py_LOCKED) != 0


# EXT
template acquire*(m: var PyMutex) = m.lock
template release*(m: var PyMutex) = m.unlock

template withLock*(m: PyMutex, body: untyped) =
  ## Acquires the given lock, executes the statements in body and
  ## releases the lock after the statements finish executing.
  bind acquire, release, SingleThread
  when not SingleThread:
    acquire(m)
    {.locks: [m].}:
      try:
        body
      finally:
        release(m)
