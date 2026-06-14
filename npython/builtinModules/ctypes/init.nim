import ../private/[utils]
import ./[decl, cdata, common, dll]
export decl
impObjects [
  pyobject,
  moduleobjectImpl,
  stringobject,
  dictobject,
  exceptions,
]

const ctypesModuleName* = "ctypes"

methodMacroTmpl(CtypesModule)

genProperty CTypesModule, "cdll", cdll, self.cdll

implCTypesModuleMethod CDLL(path: PyStrObject):
  newPyCDLL(path)

proc PyInit_ctypes*: PyObject =
  result = PyModule_CreateInitialized(ctypes)
  retIfExc result
  let modu = PyCTypesModuleObject result
  modu.cdll = newPyCDLL(newPyAscii"cdll", loadNow = false)
  modu.getDict.registerCTypeClasses()
