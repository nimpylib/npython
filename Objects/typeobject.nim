import typetraits
import strformat

import tables

import pyobject
import methodobject
import funcobjectImpl
import descrobject
import dictproxyobject
import ./pyobject_apis
import ./[
  stringobjectImpl, exceptions, boolobject, dictobject, noneobject,
  tupleobjectImpl, funcobject,
]
import ./numobjects/intobject
import ./hash
import ./pyobject_apis/attrsGeneric
export getTypeDict
import ../Utils/[
  utils,
]
import ../Python/[
  call, errors,
]


var magicNameStrs: seq[PyStrObject]
for name in magicNames:
  magicNameStrs.add newPyStr(name)

# PyTypeObject is manually declared in pyobjectBase.nim
# here we need to do some initialization
methodMacroTmpl(Type)


let pyTypeObjectType* = newPyType[PyTypeObject]("type")
# NOTE:
#[
type.__base__ is object
type(type) is type
object.__base__ is None
]# 
pyTypeObjectType.kind = PyTypeToken.Type


implTypeMagic repr:
  newPyString(self.name)

implTypeMagic str:
  newPyString(fmt"<class '{self.name}'>")

implTypeGetter dict:
  newPyDictProxy(self.dict)

implTypeSetter dict:
  newTypeError(newPyStr fmt"can't set attributes of built-in/extension type {self.name}")

pyTypeObjectType.getsetDescr["__dict__"] = (tpGetter(Type, dict), tpSetter(Type, dict))

# some generic behaviors that every type should obey
proc defaultLe(o1, o2: PyObject): PyObject {. pyCFuncPragma .} =
  let lt = o1.callMagic(lt, o2)
  let eq = o1.callMagic(eq, o2)
  lt.callMagic(Or, eq)

proc defaultNe(o1, o2: PyObject): PyObject {. pyCFuncPragma .} =
  let eq = o1.callMagic(eq, o2)
  eq.callMagic(Not)

proc defaultGe(o1, o2: PyObject): PyObject {. pyCFuncPragma .} = 
  let gt = o1.callMagic(gt, o2)
  let eq = o1.callMagic(eq, o2)
  gt.callMagic(Or, eq)

proc hashDefault(self: PyObject): PyObject {. pyCFuncPragma .} = 
  let res = cast[BiggestInt](rawHash(self))  # CPython does so
  newPyInt(res)

proc defaultEq(o1, o2: PyObject): PyObject {. pyCFuncPragma .} = 
  if rawEq(o1, o2): pyTrueObj
  else: pyFalseObj

#TODO: _Py_type_getattro_impl,_Py_type_getattro, then update ./pyobject_apis/attrs
proc addGeneric(t: PyTypeObject) = 
  template nilMagic(magicName): bool = 
    t.magicMethods.magicName.isNil

  template trySetSlot(magicName, defaultMethod) = 
    if nilMagic(magicName):
      t.magicMethods.magicName = defaultMethod

  if (not nilMagic(lt)) and (not nilMagic(eq)):
    trySetSlot(le, defaultLe)
  if (not nilMagic(eq)):
    trySetSlot(ne, defaultNe)
  if (not nilMagic(ge)) and (not nilMagic(eq)):
    trySetSlot(ge, defaultGe)
  trySetSlot(eq, defaultEq)
  trySetSlot(getattr, PyObject_GenericGetAttr)
  trySetSlot(setattr, PyObject_GenericSetAttr)
  trySetSlot(delattr, PyObject_GenericDelAttr)
  trySetSlot(repr, reprDefault)
  trySetSlot(hash, hashDefault)
  trySetSlot(str, t.magicMethods.repr)


proc type_add_members(tp: PyTypeObject, dict: PyDictObject) =
  for memb in tp.members:
    let descr = newPyMemberDescr(tp, memb)
    assert not descr.isNil
    let failed = dict.setDefaultRef(descr.name, descr) == GetItemRes.Error
    assert not failed

using self: var PyObjectObj

proc handleDelRes(call: PyObject){.cdecl, raises: [].} =
  ## logic in `slot_tp_finalize`
  let res = call
  if res.isPyNone: return
  PyErr_FormatUnraisable newPyAscii"Exception ignored while calling deallocator " #TODO:stack


proc PyObject_CallFinalizer[P](self; tp_finalize_isNil: bool) =
  let tp = self.pyType
  if tp_finalize_isNil:
    return
  handleDelRes tp.callTpDel[:P](self)

proc PyObject_CallFinalizerFromDealloc[P](self; tp_finalize_isNil: bool) =
  # tp_finalize should only be called once.
  self.callOnceFinalizerFromDealloc PyObject_CallFinalizer[P](self, tp_finalize_isNil)

proc subtype_dealloc[P](self){.pyDestructorPragma.} =
  let typ = self.pyType

  #let res = self.pyType.magicMethods.del(self)
  #self.pyType.base
  
  # Find the nearest base with a different tp_dealloc
  template tp(t: PyTypeObject): untyped = t.magicMethods
  var base = typ
  var basedealloc: destructor
  while (basedealloc = base.tp_dealloc; basedealloc) == subtype_dealloc[P]:
      base = base.base;
      assert not base.isNil
  let has_finalize = not typ.tp.del.isNil

  if has_finalize:
    PyObject_CallFinalizerFromDealloc[P](self, false)

  assert not basedealloc.isNil
  basedealloc(self)

proc type_dealloc(self){.pyDestructorPragma.} = discard
proc object_dealloc(self){.pyDestructorPragma.} = discard
pyObjectType.tp_dealloc = object_dealloc

# for internal objects
proc initTypeDict(tp: PyTypeObject) = 
  assert tp.dict.isNil
  let d = newPyDict()
  # magic methods. field loop syntax is pretty weird
  # no continue, no enumerate
  var i = -1
  for meth in tp.magicMethods.fields:
    inc i
    if not meth.isNil:
      let namePyStr = magicNameStrs[i]
      if meth is BltinFunc:
        d[namePyStr] = newPyStaticMethod(newPyNimFunc(meth, namePyStr))
      else:
        d[namePyStr] = newPyMethodDescr(tp, meth, namePyStr)

  type_add_members(tp, d)

  # getset descriptors.
  for key, value in tp.getsetDescr.pairs:
    let getter = value[0]
    let setter = value[1]
    let descr = newPyGetSetDescr(getter, setter)
    let namePyStr = newPyStr(key)
    d[namePyStr] = descr
   
  # bltin methods
  for name, meth in tp.bltinMethods.pairs:
    let namePyStr = newPyAscii(name)
    d[namePyStr] = newPyMethodDescr(tp, meth, namePyStr)

  tp.dict = d

proc typeReady*(tp: PyTypeObject) = 
  tp.pyType = pyTypeObjectType
  tp.addGeneric
  if tp.dict.isNil:
    tp.initTypeDict

pyTypeObjectType.typeReady()
pyTypeObjectType.tp_dealloc = type_dealloc


implTypeMagic call:
  # quoting CPython: "ugly exception". 
  # Deal with `type("abc") == str`. What a design failure.
  if (self == pyTypeObjectType) and (args.len == 1):
    return args[0].pyType

  let newFunc = self.magicMethods.New
  if newFunc.isNil:
    let msg = fmt"cannot create '{self.name}' instances because __new__ is not set"
    return newTypeError(newPyStr msg)
  let newObj = newFunc(@[PyObject(self)] & args)
  if newObj.isThrownException:
    return newObj
  let initFunc = self.magicMethods.init
  if not initFunc.isNil:
    let initRet = initFunc(newObj, args)
    if initRet.isThrownException:
      return initRet
    # otherwise discard
  return newObj


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
      let fun = self.getTypeDict.getOpionalItem magicNameStr
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
    return fun.fastCall(@[PyObject(self)] & args)


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

macro updateSlots(tp: PyTypeObject, dict: PyDictObject): untyped = 
  result = newStmtList()
  var idx = -1
  var m: MagicMethods
  for name, v in m.fieldpairs:
    inc idx
    let id = ident(name)
    result.add getAst(updateSlotTmpl(idx, id))

# type_new_init:type_new_alloc

implTypeMagic New(metaType: PyTypeObject, name: PyStrObject, 
                  bases: PyTupleObject, dict: PyDictObject):
  assert metaType == pyTypeObjectType
  assert bases.len == 0
  type Cls = PyInstanceObject
  let tp = newPyType[Cls]($name.str)
  tp.kind = PyTypeToken.Type
  tp.tp_dealloc = subtype_dealloc[Cls]
  tp.magicMethods.New = tpMagic(Instance, new)
  updateSlots(tp, dict)
  tp.dict = PyDictObject(tpMethod(Dict, copy)(dict))
  tp.typeReady
  # XXX: CPython's `object` doesn't contains `__del__`
  tp
