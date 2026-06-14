
import ./decl
import ../../private/[utils]
impObjects [
  pyobject,
  stringobject,
  noneobject,
  byteobjects,
  exceptions,
  numobjects/intobject,
]

imp Include, internal/pycore_global_strings

template withCStringArg(arg: PyObject, body: untyped): untyped =
  if arg.ofPyBytesObject:
    let cArg {.inject.} = PyBytesObject(arg).asCString
    body
  elif arg.ofPyStrObject:
    let cArg {.inject.} = cstring PyStrObject(arg).asUTF8
    body
  else:
    return newTypeError newPyAscii"ctypes argument must be str or bytes for now"

proc callFunction*(self: PyCFuncObject, args: openArray[PyObject], kwargs: PyObject): PyObject{.raises: [].} =
  if not kwargs.isNil:
    return newTypeError newPyAscii"keyword arguments are not implemented yet"
  if self.handle.isNil:
    return newAttributeError(self.dll, self.name)
  if self.name == pyId"Py_Initialize":
    if args.len != 0:
      return newTypeError newPyAscii"Py_Initialize takes no arguments"
    let f = cast[proc () {.cdecl, raises: [].}](self.handle)
    f()
    return pyNone
  if self.name == pyId"PyRun_SimpleString":
    if args.len != 1:
      return newTypeError newPyAscii"PyRun_SimpleString takes exactly one argument"
    withCStringArg args[0]:
      let f = cast[proc (arg: cstring): cint {.cdecl, raises: [].}](self.handle)
      return newPyInt f(cArg)
  newNotImplementedError newPyAscii"ctypes only supports Py_Initialize and PyRun_SimpleString for now"

