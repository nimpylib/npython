
import ./internal/[
  defines_gil, #pycore_pystate,  #TODO:tstate
  pycore_global_strings,
]
export pycore_global_strings

when SingleThread:
  template pyAllowThreads*(body) = body
else:
  template pyAllowThreads*(body) =
    #Py_BEGIN_ALLOW_THREADS
    body
    #Py_END_ALLOW_THREADS

import ../Objects/typeobject/apis/attrs
import ../Objects/pyobject_apis/strings
import ../Objects/[
  pyobjectBase,
  stringobject,
]

declareIntFlag PyFormatValueCode:
  FVC_NONE      0x0
  FVC_STR       0x1
  FVC_REPR      0x2
  FVC_ASCII     0x3


type conversion_func = typeof PyObject_Str
const PyEval_ConversionFuncs*: array[FVC_STR..FVC_ASCII, conversion_func] = [
    PyObject_Str, PyObject_Repr, PyObject_ASCII
]


type
  PySpecialMethod = object
    name*: PyStrObject
    error*: string
    error_suggestion*: string
  Special = enum
    Enter,
    Exit,
    AEnter,
    AExit

template newPySpecialMethod(nam: string, err: string, extra_error_suggestion: string): PySpecialMethod =
  PySpecialMethod(
    name: pyDUId nam,
    error: err,
    error_suggestion: err & extra_error_suggestion
  )

const meanWith = " but it supports the context manager protocol. Did you mean to use 'with'?"
const meanAsyncWith = " but it supports the asynchronous context manager protocol. Did you mean to use 'async with'?"
let Py_SpecialMethods: array[Special, PySpecialMethod] = [
  newPySpecialMethod(
    "enter",
    "'%T' object does not support the context manager protocol (missed __enter__ method)",
    meanAsyncWith
  ),
  newPySpecialMethod(
    "exit",
    "'%T' object does not support the context manager protocol (missed __exit__ method)",
    meanAsyncWith
  ),
  newPySpecialMethod(
    "aenter",
    "'%T' object does not support the asynchronous context manager protocol (missed __aenter__ method)",
    meanWith
  ),
  newPySpecialMethod(
    "aexit",
    "'%T' object does not support the asynchronous context manager protocol (missed __aexit__ method)",
    meanWith
  )
]


proc getSpecialFromOpArg*(opArg: int): PySpecialMethod =
  Py_SpecialMethods[Special opArg]

proc type_has_special_method(cls: PyTypeObject, name: PyStrObject): bool =
    ##  Check if a 'cls' provides the given special method.
    # _PyType_Lookup() does not set an exception and returns a borrowed ref
    #assert(!PyErr_Occurred());
    let r = PyType_LookupRef(cls, name)
    return not r.isNil and not r.pyType.magicMethods.get.isNil;

proc PyEval_SpecialMethodCanSuggest*(self: PyObject, oparg: int): bool =
  ## inner
  let typ = self.pyType
  case Special(oparg):
    of Enter, Exit:
        type_has_special_method(typ, pyDUId(aenter)) and
            type_has_special_method(typ, pyDUId(aexit))
    of AEnter, AExit:
        type_has_special_method(typ, pyDUId(enter)) and
            type_has_special_method(typ, pyDUId(exit))

