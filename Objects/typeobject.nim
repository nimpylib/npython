
import strformat

import tables

import pyobject
import dictproxyobject
import ./pyobject_apis
import ./[
  stringobjectImpl, exceptions, dictobject,
  tupleobjectImpl,
]
import ./numobjects/intobject
import ./hash
import ./pyobject_apis/attrsGeneric
export getTypeDict
import ./typeobject/[
  decl,
  utils, object_new_init,
  type_ready,
]
export decl, type_ready

import ../Include/internal/[
  defines_gil,
]


# PyTypeObject is manually declared in pyobjectBase.nim
# here we need to do some initialization
methodMacroTmpl(Type)

genProperty Type, "__base__", base, self.base

implTypeMagic repr:
  newPyString(self.name)

implTypeMagic str:
  newPyString(fmt"<class '{self.name}'>")

genProperty Type, "__dict__", dict, newPyDictProxy(self.dict):
  newTypeError(newPyStr fmt"can't set attributes of built-in/extension type {self.name}")


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


pyTypeObjectType.pyType = pyTypeObjectType
pyTypeObjectType.typeReadyImpl(true)
pyTypeObjectType.tp_dealloc = type_dealloc


pyObjectType.magicMethods.New = object_new_wrap
pyObjectType.magicMethods.init = object_init_wrap

# BEGIN_TYPE_LOCK & END_TYPE_LOCK
when SingleThread:
  template withTYPE_LOCK(body) = body
else:
  import std/locks
  var typeLock: Lock
  template withTYPE_LOCK(body) =
    withLock typeLock: body

proc init_static_type(self: PyTypeObject, isbuiltin: bool, initial: bool) =
  withTYPE_LOCK:
    typeReadyImpl(self, initial)

proc PyStaticType_InitBuiltin*(typ: PyTypeObject): PyBaseErrorObject =
  #TODO:interp
  #TODO:Py_IsMainInterpreter
  const Py_IsMainInterpreter = true
  init_static_type(typ, true, Py_IsMainInterpreter)

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

