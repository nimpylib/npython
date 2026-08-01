
include ./comm
import ../../decl
import ./consts

import ./abi_consts
import ./ffi_full/[
  utils,
]
impObjects [
  tupleobject,
  typeobject,
  dictobject,
]
imp Python, getargs/dispatch

import ./libffi
proc newCFuncType*(restype: PyObject, argtypes: openArray[PyObject], abi = DEFAULT_ABI): PyObject {.raises: [].} =
  let retInfo = ctypeInfo(restype, allowVoidInC = true)
  if retInfo.ffiType.isNil:
    return unsupportedCType(restype)
  for argtype in argtypes:
    if ctypeInfo(argtype, allowVoidInC = false).ffiType.isNil:
      return unsupportedCType(argtype)
  let typ = newPyType[PyCFuncObject]("CFunctionType", base = pyCFuncObjectType)
  typ.pyType = pyTypeObjectType
  typ.kind = PyTypeToken.Type
  typ.magicMethods.New = pyCFuncObjectType.magicMethods.New
  typ.typeReady true
  let dict = PyDictObject typ.dict
  dict[newPyAscii"_restype_"] = restype
  dict[newPyAscii"_argtypes_"] = newPyTuple(argtypes)
  dict[newPyAscii AbiAttrName] = newPyInt(ord abi)
  typ


methodMacroTmpl CtypesModule
template gen(CFUNCTYPE, DEFAULT_ABI) {.dirty.} =
  proc CFUNCTYPE*(restype: PyObject, argtypes: openArray[PyObject]): PyObject =
    newCFuncType(restype, argtypes, DEFAULT_ABI)
  implCtypesModuleMethod CFUNCTYPE(restype, *argtypes):
    CFUNCTYPE(restype, argtypes)
  

gen CFUNCTYPE, DEFAULT_ABI
gen PYFUNCTYPE, DEFAULT_ABI

when defined(windows):
  gen WINFUNCTYPE, STDCALL


