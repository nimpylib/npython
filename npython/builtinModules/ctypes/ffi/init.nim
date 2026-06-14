
import ./[decl, ffi,]
export decl
import ../../private/[utils]
impObjects [
  pyobject,
]

methodMacroTmpl(CFunc)

implCFuncMagic call:
  callFunction(self, args, kwargs)
