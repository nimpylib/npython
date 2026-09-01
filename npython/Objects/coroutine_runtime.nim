import pyobject
import coroutineobject
import sleepobject
import ../Python/neval
from ../Utils/utils import `!!`
import ./exceptions
import ./stringobject
import ./noneobject
from pkg/pytime import sleep

proc runAwaitable*(obj: PyObject): PyObject =
  if obj.ofPySleepAwaitableObject:
    ValueError!!
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
  result = coro.frame.evalFrame
  coro.running = false
  retIfExc result
  if not coro.frame.completed:
    return newRuntimeError(newPyAscii("coroutine suspended without completion"))
  coro.finished = true

proc runCoroutine*(obj: PyObject): PyObject =
  if not obj.ofPyCoroutineObject:
    return newTypeError(newPyAscii("a coroutine was expected"))
  runAwaitable(obj)
