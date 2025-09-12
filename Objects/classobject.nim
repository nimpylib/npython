
import std/strformat
import ./[
  pyobject,
  exceptions,
  typeobject,
  noneobject,
  stringobject,
]
import ./typeobject/utils

import ../Utils/[
  utils,
]
import ../Python/[
  call,
]


# create user defined class
# As long as relying on Nim GC it's hard to do something like variable length object
# as in CPython, so we have to use a somewhat traditional and clumsy way
# The type declared here is never used, it's needed as a placeholder to declare magic
# methods.
declarePyType Instance(dict):
  discard


# todo: should move to the base object when inheritance and mro is ready
# todo: should support more complicated arg declaration
implInstanceMagic New(tp: PyTypeObject, *actualArgs):
  result = newPyInstanceSimple()
  result.pyType = tp

template instanceUnaryMethodTmpl(idx: int, nameIdent: untyped, isDel: bool) = 
  implInstanceMagic nameIdent:
    let magicNameStr = magicNameStrs[idx]
    when isDel:
      result = pyNone
      # Execute __del__ method, if any.
      let fun = self.getTypeDict.getOptionalItem magicNameStr
      if fun.isNil: return
    else:
      let fun = KeyError!self.getTypeDict[magicNameStr]
    result = fun.fastCall([PyObject(self)])
    when isDel:
      handleDelRes result
      result = pyNone

template instanceBinaryMethodTmpl(idx: int, nameIdent: untyped) = 
  implInstanceMagic nameIdent:
    let magicNameStr = magicNameStrs[idx]
    let fun = KeyError!self.getTypeDict[magicNameStr]
    return fun.fastCall([PyObject(self), other])

template instanceTernaryMethodTmpl(idx: int, nameIdent: untyped) = 
  implInstanceMagic nameIdent:
    let magicNameStr = magicNameStrs[idx]
    let fun = KeyError!self.getTypeDict[magicNameStr]
    return fun.fastCall([PyObject(self), arg1, arg2])

template instanceBltinFuncTmpl(idx: int, nameIdent: untyped) = 
  implInstanceMagic nameIdent:
    let magicNameStr = magicNameStrs[idx]
    let fun = KeyError!self.getTypeDict[magicNameStr]
    return fun.fastCall(args)

template instanceBltinMethodTmpl(idx: int, nameIdent: untyped) = 
  implInstanceMagic nameIdent:
    let magicNameStr = magicNameStrs[idx]
    let fun = KeyError!self.getTypeDict[magicNameStr]
    return fun.fastCall(@[PyObject(self)] & @args)


macro implInstanceMagics: untyped = 
  result = newStmtList()
  var idx = -1
  var m: MagicMethods
  for name, v in m.fieldpairs:
    inc idx
    # no `continue` can be used...
    if name != "New":
      if v is UnaryMethod:
        let isDel = name == "del"
        result.add getAst(instanceUnaryMethodTmpl(idx, ident(name), isDel))
      elif v is BinaryMethod:
        result.add getAst(instanceBinaryMethodTmpl(idx, ident(name)))
      elif v is TernaryMethod:
        result.add getAst(instanceTernaryMethodTmpl(idx, ident(name)))
      elif v is BltinFunc:
        result.add getAst(instanceBltinFuncTmpl(idx, ident(name)))
      elif v is BltinMethod:
        result.add getAst(instanceBltinMethodTmpl(idx, ident(name)))
      else:
        assert false

implInstanceMagics


template updateSlotTmpl(idx: int, slotName) = 
  let magicNameStr = magicNameStrs[idx]
  if dict.hasKey(magicnameStr):
    tp.magicMethods.`slotName` = tpMagic(Instance, slotName)

macro updateSlots*(tp: PyTypeObject, dict: PyDictObject): untyped = 
  result = newStmtList()
  var idx = -1
  var m: MagicMethods
  for name, v in m.fieldpairs:
    inc idx
    let id = ident(name)
    result.add getAst(updateSlotTmpl(idx, id))
