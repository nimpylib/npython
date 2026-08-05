import ../Objects/[
  pyobject,
  moduleobjectImpl,
  dictobjectImpl,
  methodobject,
  noneobject,
  noneobjectImpl,
  stringobject,
  coroutine_runtime,
]
import ../Python/getargs/[dispatch, nokw]
import ../Objects/exceptions/baseapi

const asyncioModuleName* = "asyncio"

proc asyncioRun(args: openArray[PyObject]; kwargs: PyObject): PyObject {.cdecl.} =
  PyArg_NoKw("run", kwargs)
  checkArgNum 1, "run"
  runCoroutine(args[0])

proc asyncioSleep(args: openArray[PyObject]; kwargs: PyObject): PyObject {.cdecl.} =
  PyArg_NoKw("sleep", kwargs)
  checkArgNum 1, "sleep"
  pyNone

proc PyInit_asyncio*: PyObject =
  let module = newPyModule(asyncioModuleName)
  module.getDict[newPyAscii("run")] = newPyNimFunc(asyncioRun, newPyAscii("run"))
  module.getDict[newPyAscii("sleep")] = newPyNimFunc(asyncioSleep, newPyAscii("sleep"))
  module
