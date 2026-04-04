

import std/strformat
import pyobject
import noneobject
import exceptions
import stringobject
import methodobject
import ../Include/descrobject as incDescr
export incDescr

#import ../Python/getargs/vargs
import ./typeobject/apis/subtype

import ../Utils/utils

# method descriptor

declarePyType CommonMethodDescr():
  name: PyStrObject
  dType: PyTypeObject
  kind: NFunc
  meth: int # the method function pointer. Have to be int to make it generic.

declarePyType MethodDescr(base(CommonMethodDescr)):
  discard


template newXxMethodDescrTmpl(PyType, FunType){.dirty.} =
  proc `newPy PyType`*(t: PyTypeObject, 
                         meth: FunType,
                         name: PyStrObject,
                         ): `Py PyType Object` = 
    result = `newPy PyType Simple`()
    result.dType = t
    result.kind = NFunc.FunType
    assert result.kind != NFunc.BltinFunc
    result.meth = cast[int](meth)
    result.name = name

template newMethodDescrTmpl(FunType) =
  newXxMethodDescrTmpl MethodDescr, FunType

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

template descr_check*(self, other){.dirty.} =
  ## XXX: CPython's `descr_setcheck` just does the same as `descr_check`
  bind fmt, formatValue, newTypeError, newPyStr, PyObject_TypeCheck
  if not PyObject_TypeCheck(other, self.dType):
    let oname = other.typeName
    let msg = fmt"descriptor {self.name} for {self.dType.name} objects " &
      fmt"doesn't apply to {oname} object"
    return newTypeError(newPyStr msg)

implMethodDescrMagic get:
  descr_check(self, other)
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


declarePyType ClassMethodDescr(base(CommonMethodDescr)): discard


template newClassMethodDescrTmpl(FunType) =
  newXxMethodDescrTmpl ClassMethodDescr, FunType

# newPyClassMethodDescr
newClassMethodDescrTmpl BltinMethod

proc `$?`*(descr: PyCommonMethodDescrObject): string =
  ## inner. unstable.
  # PyErr_Format ... "%V" .. "?"
  if descr.name.isNil: "?" else: $descr.name

proc truncedTypeName*(descr: PyCommonMethodDescrObject): string =
  ## inner. unstable.
  # %.100s with `PyDescr_TYPE(descr)->tp_name`
  descr.dType.name.substr(0, 99)

proc classmethod_getImpl(descr: PyCommonMethodDescrObject, obj: PyObject, typ: PyTypeObject): PyObject =
  assert not typ.isNil
  if not typ.isSubtype descr.dType:
    return newTypeError newPyStr(
      fmt"descriptor '{$?descr}' requires a subtype of '{descr.truncedTypeName}' " &
        fmt"but received '{typ.name:.100s}'"
    )
  var cls = PyTypeObject nil
  #if descr.isMETH_METHOD:
  cls = descr.dType
  assert descr.kind == NFunc.BltinMethod
  newPyNimFunc(cast[BltinMethod](descr.meth), descr.name, cls)

proc classmethod_get(descr: PyCommonMethodDescrObject, obj: PyObject, typ: PyTypeObject = nil): PyObject =
  var typ = typ
  if typ.isNil:
    if not obj.isNil:
      typ = obj.pyType
    else:
      # Wot - no type?!
      return newTypeError newPyStr(
      fmt"descriptor '{$?descr}' for type '{descr.truncedTypeName}' " &
        "needs either and object or a type")
  classmethod_getImpl(descr, obj, typ)

proc classmethod_get*(self: PyObject, obj: PyObject, typ: PyObject = nil): PyObject =
  ## inner
  let descr = PyCommonMethodDescrObject self
  # Ensure a valid type.  Class methods ignore obj.
  if not typ.isNil and not typ.ofPyTypeObject:
    return newTypeError newPyStr(
      fmt"descriptor '{$?descr}' for type '{descr.truncedTypeName}' " &
        fmt"needs a type, not a '{typ.typeName:.100s}' as arg 2"
    )
  classmethod_get(descr, obj, PyTypeObject typ)

implClassMethodDescrMagic get:
  classmethod_get(self, nil, other)

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



declarePyType MemberDescr():
  name: PyStrObject
  dType: PyTypeObject
  d_member: PyMemberDef

proc newPyMemberDescr*(tp: PyTypeObject, member: PyMemberDef): PyMemberDescrObject =
  member.noRelOff "PyDescr_NewMember"
  result = newPyMemberDescrSimple()
  result.dType = tp
  result.name = newPyStr member.name
  result.d_member = member


# __get__, __set__ are in ./descrobjectImpl
