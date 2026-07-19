
import ./[decl, ffi,]
export decl
import ../../private/[utils]
import ../../../Objects/exceptions/baseapi
import ../../../Objects/exceptions
import ../../../Objects/stringobject
import pkg/libffi
impObjects [
  pyobject,
  noneobject,
  bltcommon,
  typeobject,
]

methodMacroTmpl(CFunc)
imp Python, getargs/nokw

implCFuncMagic call:
  callFunction(self, args, kwargs)
implCFuncMagic New(tp: PyTypeObject, callback: PyObject):
  newPyCallback(tp, callback)

implCFuncMagic del:
  if not self.closure.isNil:
    closure_free(self.closure)
    self.closure = nil
  pyNone
