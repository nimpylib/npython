

import ../../Objects/pyobjectBase

#[
const SingleThread = not compileOption("threads")

when SingleThread:
  template withPyCriticalSection*(_; body) = block: body
else:
  type
    PyCriticalSection = object
      ##[NOTE: the contents of this struct are private and may change betweeen
      Python releases without a deprecation period.
      ]##
      prev: uint
      mutex: PyMutex
    PyCriticalSection2 = object of PyCriticalSection
      ##[A critical section protected by two mutexes. Use
Py_BEGIN_CRITICAL_SECTION2 and Py_END_CRITICAL_SECTION2.
NOTE: the contents of this struct are private and may change betweeen
Python releases without a deprecation period.]##
      mutex2: PyMutex
  
  template withPyCriticalSection*(op; body) =
    block:
      var pycs: PyCriticalSection

      body
  using c: PyCriticalSection
  proc beginMutex(c; m: PyMutex) =


  proc PyCriticalSection_Begin(c; op: PyObject) =
    beginMutex(c, op.mutex)
]#

#TODO:mutex
template criticalRead*(self: PyObject; body) =
  if self.writeLock:
    return newLockError newPyAscii"Read failed because object is been written."
  inc self.readNum
  try: body
  finally:
    dec self.readNum

template criticalWrite*(self: PyObject; body) =
  if 0 < self.readNum or self.writeLock:
    return newLockError newPyAscii"Write failed because object is been read or written."
  self.writeLock = true
  try: body
  finally:
    self.writeLock = false
