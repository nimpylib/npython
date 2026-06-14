import std/dynlib

import ../private/[utils]
import ./common
import pkg/handy_sugars/trans_imp
impExpCwd dll, [
  decl,
]
impExpCwd ffi, [
  init,
]

impObjects [
  pyobject,
  stringobject,
  dictobject,
  exceptions,
  noneobject,
]

methodMacroTmpl(CDLL)
methodMacroTmpl(CFunc)

using self: PyCDLLObject

proc newPyCDLL*(path: PyStrObject, loadNow = true): PyCDLLObject{.raises: [].} =
  result = newPyCDLLSimple()
  result.path = path
  if loadNow:
    result.handle = loadLib(path.asUTF8)

proc getHandle(self: PyCDLLObject): LibHandle{.raises: [].} =
  if self.handle.isNil:
    self.handle = loadLib(self.path.asUTF8)
  self.handle

proc getDict*(self): PyDictObject{.raises: [].} =
  result = PyDictObject self.dict
  assert not result.isNil

proc getDict*(self: PyCFuncObject): PyDictObject{.raises: [].} =
  result = PyDictObject self.dict
  assert not result.isNil

proc newPyCFunc*(dll: PyCDLLObject, name: PyStrObject): PyCFuncObject{.raises: [].} =
  result = newPyCFuncSimple()
  result.dll = dll
  result.name = name
  result.handle = symAddr(dll.getHandle, cstring name.asUTF8)


implCDLLMagic getattr:
  let name = other.attrName
  let selfDict = self.getDict
  let existing = selfDict.getOptionalItem(name)
  if not existing.isNil:
    return existing
  let cfunc = newPyCFunc(self, name)
  selfDict[name] = cfunc
  cfunc

implCDLLMagic setattr:
  let name = arg1.attrName
  self.getDict[name] = arg2
  pyNone

implCDLLMagic getitem:
  if not other.ofPyStrObject:
    return newTypeError newPyAscii"library name must be a string"
  newPyCDLL(PyStrObject other)

#FIXME: argtypes and restype should be fully manipulated by `{.member.}` in the CFuncObject
# instead of hacking it in getattr and setattr.
implCFuncMagic getattr:
  let name = other.attrName
  if name.eqAscii"argtypes":
    return self.argtypes.nil2none
  if name.eqAscii"restype":
    return self.restype.nil2none
  let selfDict = self.getDict
  let existing = selfDict.getOptionalItem(name)
  if not existing.isNil:
    return existing
  newAttributeError(self, name)

implCFuncMagic setattr:
  let name = arg1.attrName
  if name.eqAscii"argtypes":
    self.argtypes = arg2
    return pyNone
  if name.eqAscii"restype":
    self.restype = arg2
    return pyNone
  self.getDict[name] = arg2
  pyNone
