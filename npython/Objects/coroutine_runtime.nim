import pyobject
import coroutineobject
import sleepobject
import ../Python/neval
import ./exceptions
import ./stringobject
import ./noneobject
import std/os

proc runAwaitable*(obj: PyObject): PyObject =
  if obj.ofPySleepAwaitableObject:
    when not defined(js):
      sleep PySleepAwaitableObject(obj).milliseconds
    return pyNone
  if not obj.ofPyCoroutineObject:
    return obj
  let coro = PyCoroutineObject(obj)
  if coro.finished:
    return newRuntimeError(newPyAscii("cannot reuse already awaited coroutine"))
  if coro.running:
    return newRuntimeError(newPyAscii("coroutine already executing"))
  coro.running = true
  let result = coro.frame.evalFrame
  coro.running = false
  if result.isThrownException:
    return result
  if not coro.frame.completed:
    return newRuntimeError(newPyAscii("coroutine suspended without completion"))
  coro.finished = true
  result

proc runCoroutine*(obj: PyObject): PyObject =
  if not obj.ofPyCoroutineObject:
    return newTypeError(newPyAscii("a coroutine was expected"))
  runAwaitable(obj)
