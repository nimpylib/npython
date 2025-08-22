import typetraits
import strformat

import tables

import pyobject
import bundle
import methodobject
import funcobjectImpl
import descrobject
import dictproxyobject
import ./pyobject_apis
import ./hash
import ../Utils/utils
import ../Python/call


var magicNameStrs: seq[PyStrObject]
for name in magicNames:
  magicNameStrs.add newPyStr(name)

# PyTypeObject is manually declared in pyobjectBase.nim
# here we need to do some initialization
methodMacroTmpl(Type)


let pyTypeObjectType* = newPyType("type")
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

proc getTypeDict*(obj: PyObject): PyDictObject = 
  PyDictObject(obj.pyType.dict)

# some generic behaviors that every type should obey
proc defaultLe(o1, o2: PyObject): PyObject {. cdecl .} =
  let lt = o1.callMagic(lt, o2)
  let eq = o1.callMagic(eq, o2)
  lt.callMagic(Or, eq)

proc defaultNe(o1, o2: PyObject): PyObject {. cdecl .} =
  let eq = o1.callMagic(eq, o2)
  eq.callMagic(Not)

proc defaultGe(o1, o2: PyObject): PyObject {. cdecl .} = 
  let gt = o1.callMagic(gt, o2)
  let eq = o1.callMagic(eq, o2)
  gt.callMagic(Or, eq)

proc hashDefault(self: PyObject): PyObject {. cdecl .} = 
  let res = cast[BiggestInt](rawHash(self))  # CPython does so
  newPyInt(res)

proc defaultEq(o1, o2: PyObject): PyObject {. cdecl .} = 
  if rawEq(o1, o2): pyTrueObj
  else: pyFalseObj


# generic getattr
proc getAttr(self: PyObject, nameObj: PyObject): PyObject {. cdecl .} =
  let name = nameObj.asAttrNameOrRetE
  let typeDict = self.getTypeDict
  if typeDict.isNil:
    unreachable("for type object dict must not be nil")
  var descr: PyObject
  typeDict.withValue(name, value):
    descr = value[]
    let descrGet = descr.pyType.magicMethods.get
    if not descrGet.isNil:
      return descr.descrGet(self)

  if self.hasDict:
    let instDict = PyDictObject(self.getDict)
    instDict.withValue(name, val):
      return val[]

  if not descr.isNil:
    return descr

  return newAttributeError(self, name)
  
# generic getattr
proc setAttr(self: PyObject, nameObj: PyObject, value: PyObject): PyObject {. cdecl .} =
  let name = nameObj.asAttrNameOrRetE
  let typeDict = self.getTypeDict
  if typeDict.isNil:
    unreachable("for type object dict must not be nil")
  var descr: PyObject
  typeDict.withValue(name, val):
    descr = val[]
    let descrSet = descr.pyType.magicMethods.set
    if not descrSet.isNil:
      return descr.descrSet(self, value)
      
  template retAttributeError =  
    return newAttributeError(self, name)
  if self.hasDict:
    let instDict = PyDictObject(self.getDict)
    if value.isNil:
      let res = instDict.delitemImpl(name)
      if res != pyNone:
        assert res.pyType != pyTypeErrorObjectType
        retAttributeError
    else:
      instDict[name] = value
    return pyNone
  retAttributeError

proc delAttr(self: PyObject, nameObj: PyObject): PyObject {. cdecl .} =
  setAttr(self, nameObj, nil)

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
  trySetSlot(getattr, getAttr)
  trySetSlot(setattr, setAttr)
  trySetSlot(delattr, delAttr)
  trySetSlot(repr, reprDefault)
  trySetSlot(hash, hashDefault)
  trySetSlot(str, t.magicMethods.repr)


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

template instanceUnaryMethodTmpl(idx: int, nameIdent: untyped) = 
  implInstanceMagic nameIdent:
    let magicNameStr = magicNameStrs[idx]
    let fun = self.getTypeDict[magicNameStr]
    return fun.fastCall([PyObject(self)])

template instanceBinaryMethodTmpl(idx: int, nameIdent: untyped) = 
  implInstanceMagic nameIdent:
    let magicNameStr = magicNameStrs[idx]
    let fun = self.getTypeDict[magicNameStr]
    return fun.fastCall([PyObject(self), other])

template instanceTernaryMethodTmpl(idx: int, nameIdent: untyped) = 
  implInstanceMagic nameIdent:
    let magicNameStr = magicNameStrs[idx]
    let fun = self.getTypeDict[magicNameStr]
    return fun.fastCall([PyObject(self), arg1, arg2])

template instanceBltinFuncTmpl(idx: int, nameIdent: untyped) = 
  implInstanceMagic nameIdent:
    let magicNameStr = magicNameStrs[idx]
    let fun = self.getTypeDict[magicNameStr]
    return fun.fastCall(args)

template instanceBltinMethodTmpl(idx: int, nameIdent: untyped) = 
  implInstanceMagic nameIdent:
    let magicNameStr = magicNameStrs[idx]
    let fun = self.getTypeDict[magicNameStr]
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
        result.add getAst(instanceUnaryMethodTmpl(idx, ident(name)))
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

template updateSlotTmpl(idx: int, slotName: untyped) = 
  let magicNameStr = magicNameStrs[idx]
  if dict.hasKey(magicnameStr):
    tp.magicMethods.`slotName` = tpMagic(Instance, slotname)

macro updateSlots(tp: PyTypeObject, dict: PyDictObject): untyped = 
  result = newStmtList()
  var idx = -1
  var m: MagicMethods
  for name, v in m.fieldpairs:
    inc idx
    result.add getAst(updateSlotTmpl(idx, ident(name)))

implTypeMagic New(metaType: PyTypeObject, name: PyStrObject, 
                  bases: PyTupleObject, dict: PyDictObject):
  assert metaType == pyTypeObjectType
  assert bases.len == 0
  let tp = newPyType($name.str)
  tp.kind = PyTypeToken.Type
  tp.magicMethods.New = tpMagic(Instance, new)
  updateSlots(tp, dict)
  tp.dict = PyDictObject(tpMethod(Dict, copy)(dict))
  tp.typeReady
  tp
