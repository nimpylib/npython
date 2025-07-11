import strformat

import pyobject
import noneobject
import exceptions
import stringobject
import methodobject

import ../Python/call
import ../Utils/utils

# method descriptor

declarePyType MethodDescr():
  name: PyStrObject
  dType: PyTypeObject
  kind: NFunc
  meth: int # the method function pointer. Have to be int to make it generic.


template newMethodDescrTmpl(FunType) = 
  proc newPyMethodDescr*(t: PyTypeObject, 
                         meth: FunType,
                         name: PyStrObject,
                         ): PyMethodDescrObject = 
    result = newPyMethodDescrSimple()
    result.dType = t
    result.kind = NFunc.FunType
    assert result.kind != NFunc.BltinFunc
    result.meth = cast[int](meth)
    result.name = name


newMethodDescrTmpl(UnaryMethod)
newMethodDescrTmpl(BinaryMethod)
newMethodDescrTmpl(TernaryMethod)
newMethodDescrTmpl(BltinMethod)
# placeholder to fool compiler in typeobject.nim when initializing type dict
proc newPyMethodDescr*(t: PyTypeObject, 
                       meth: BltinFunc, 
                       name: PyStrObject
                       ): PyMethodDescrObject = 
  unreachable("bltin function shouldn't be method. " & 
    "This is a placeholder to fool the compiler")


implMethodDescrMagic get:
  if other.pyType != self.dType:
    let msg = fmt"descriptor {self.name} for {self.dType.name} objects " &
      fmt"doesn't apply to {other.pyType.name} object"
    return newTypeError(msg)
  let owner = other
  case self.kind
  of NFunc.BltinFunc:
    return newPyNimFunc(cast[BltinFunc](self.meth), self.name)
  of NFunc.UnaryMethod:
    return newPyNimFunc(cast[UnaryMethod](self.meth), self.name, owner)
  of NFunc.BinaryMethod:
    return newPyNimFunc(cast[BinaryMethod](self.meth), self.name, owner)
  of NFunc.TernaryMethod:
    return newPyNimFunc(cast[TernaryMethod](self.meth), self.name, owner)
  of NFunc.BltinMethod:
    return newPyNimFunc(cast[BltinMethod](self.meth), self.name, owner)

# get set descriptor
# Nim level property decorator

declarePyType GetSetDescr():
  getter: UnaryMethod
  setter: BinaryMethod

implGetSetDescrMagic get:
  self.getter(other)

implGetSetDescrMagic set:
  self.setter(arg1, arg2)

proc newPyGetSetDescr*(getter: UnaryMethod, setter: BinaryMethod): PyObject = 
  let descr = newPyGetSetDescrSimple()
  descr.getter = getter
  descr.setter = setter
  descr


# property decorator
declarePyType Property():
  getter: PyObject
  # setter, deleter not implemented

implPropertyMagic init:
  # again currently only have getter
  checkArgNum(1)
  self.getter = args[0]
  pyNone

implPropertyMagic get:
  fastCall(self.getter, @[other])

