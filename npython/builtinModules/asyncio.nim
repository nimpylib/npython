import ../Objects/[
  pyobject,
  moduleobjectImpl,
  noneobject,
  noneobjectImpl,
  stringobject,
  sleepobject,
  numobjects,
  exceptionsImpl,
]
import ./private/gen
import ../Python/getargs/dispatch
import ../Python/[builtindict, call]
import ../Objects/dictobject/ops
import ../Objects/exceptions/baseapi

genModule asyncio

implAsyncioModuleMethod run(coro: PyObject):
  let runner = bltinDict.getOptionalItem(newPyAscii "__npy_runAwaitable")
  if runner.isNil:
    return newRuntimeError(newPyAscii "awaitable runtime is not initialized")
  runner.call(coro)

implAsyncioModuleMethod sleep(delay: PyObject):
  var milliseconds: int
  if delay.ofPyIntObject:
    var overflow: bool
    let seconds = PyIntObject(delay).toFloat(overflow)
    if overflow:
      return newOverflowError(newPyAscii("sleep delay is too large"))
    milliseconds = int(seconds * 1000.0)
  elif delay.ofPyFloatObject:
    milliseconds = int(PyFloatObject(delay).v * 1000.0)
  else:
    return newTypeError(newPyAscii("sleep() delay must be a number"))
  if milliseconds < 0:
    return newValueError(newPyAscii("sleep length must be non-negative"))
  newPySleepAwaitable(milliseconds)
