import typetraits
import strformat

import tables

import pyobject
import methodobject
import descrobject
import dictproxyobject
import ./pyobject_apis
import ./[
  stringobjectImpl, exceptions, boolobject, dictobject,
  tupleobjectImpl, funcobject,
]
import ./numobjects/intobject
import ./hash
import ./pyobject_apis/attrsGeneric
export getTypeDict
import ./typeobject/[
  utils, object_new_init,
]

import ../Utils/[
  utils,
]

pyObjectType.magicMethods.New = object_new_wrap
pyObjectType.magicMethods.init = object_init_wrap

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


genProperty Type, "__base__", base, self.base

implTypeMagic repr:
  newPyString(self.name)

implTypeMagic str:
  newPyString(fmt"<class '{self.name}'>")

genProperty Type, "__dict__", dict, newPyDictProxy(self.dict):
  newTypeError(newPyStr fmt"can't set attributes of built-in/extension type {self.name}")

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
proc PyObject_CallFinalizer[P](self; tp_finalize_isNil: bool) =
  let tp = self.pyType
  if tp_finalize_isNil:
    return
  handleDelRes tp.callTpDel[:P](self)

proc PyObject_CallFinalizerFromDealloc[P](self; tp_finalize_isNil: bool) =
  # tp_finalize should only be called once.
  self.callOnceFinalizerFromDealloc PyObject_CallFinalizer[P](self, tp_finalize_isNil)

proc subtype_dealloc*[P](self){.pyDestructorPragma.} =
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
  let newObj = newFunc(@[PyObject(self)] & @args, kwargs)
  if newObj.isThrownException:
    return newObj
  let initFunc = self.magicMethods.init
  if not initFunc.isNil:
    let initRet = initFunc(newObj, args, kwargs)
    if initRet.isThrownException:
      return initRet
    # otherwise discard
  return newObj

