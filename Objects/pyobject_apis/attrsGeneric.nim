
import ../[
  pyobject, exceptions,
  stringobject,
  dictobject,
  noneobject,
]
import ./attrsUtils
import ../../Utils/utils

proc getTypeDict*(obj: PyObject|PyObjectObj): PyDictObject = 
  PyDictObject(obj.pyType.dict)

type
  PyStackRef* = PyObject
  PyCStackRef* = object
    `ref`: PyStackRef  ## Nim ref can be used as stackref
const PyStackRef_NULL* = default PyStackRef
template PyThreadState_PushCStackRef*(c) = discard
proc pushedCStackRef*(): PyCStackRef = discard
template asPyObjectBorrow*(r: PyStackRef): lent PyObject = r  ## PyStackRef_AsPyObjectBorrow
template asPyObjectSteal*(r: PyStackRef): PyObject = r  ## PyStackRef_AsPyObjectSteal
proc isNull*(self: PyStackRef): bool =
  ## PyStackRef_IsNull
  self.isNil

proc PyStackRef_FromPyObjectSteal*(o: PyObject): PyStackRef = o

proc find_name_in_mro(tp: PyTypeObject, name: PyStrObject, error: var int): PyObject =
  for base in tp.iterMro:
    let dicto = base.dict
    assert not dicto.isNil and dicto.ofPyDictObject
    let dict = PyDictObject dicto
    result = dict.getOptionalItem(name)
    if not result.isNil:
      return
  error = 0

proc PyType_LookupStackRefAndVersion*(tp: PyTypeObject, name: PyStrObject, o: var PyObject): uint{.discardable.} =
  ## `_PyType_LookupStackRefAndVersion`
  var error: int
  let res = find_name_in_mro(tp, name, error)
  if error != 0:
    o = PyStackRef_NULL
    return
  o = PyStackRef_FromPyObjectSteal res


proc PyObject_GenericGetAttrWithDict*(self: PyObject; name: PyStrObject|PyObject,
    typeDict: PyDictObject = self.getTypeDict, suppress: static[bool] = false): PyObject{.pyCFuncPragma.} =
  ## `_PyObject_GenericGetAttrWithDict`
  ## returns nil if suppress and not found
  nameAsStr
  if typeDict.isNil:
    unreachable("for type object dict must not be nil")
  when suppress:
    template SuppressAE = return nil
  var descr: PyObject

  let tp = self.pyType
  var cref = pushedCStackRef()
  PyType_LookupStackRefAndVersion(tp, name, cref.`ref`)
  descr = asPyObjectBorrow cref.`ref`

  template tryDescr =
    let descrGet = descr.pyType.magicMethods.get
    if not descrGet.isNil:
      result = descrGet(descr, self)
      when suppress:
        if result.isExceptionOf Attribute:
          SuppressAE
      else: return
  if not descr.isNil: tryDescr

  typeDict.withValue(name, value):
    descr = value[]
    tryDescr

  if self.hasDict:
    let instDict = PyDictObject(self.getDict)
    instDict.withValue(name, val):
      return val[]

  if not descr.isNil:
    return descr

  when suppress: SuppressAE
  else: return newAttributeError(self, name)

proc PyObject_GenericGetAttrWithDict*(self: PyObject; name: PyStrObject|PyObject,
    typeDict: typeof(nil), suppress: static[bool] = false): PyObject{.pyCFuncPragma.} =
  PyObject_GenericGetAttrWithDict(self, name, suppress=suppress)

proc PyObject_GenericGetAttr*(self: PyObject, name: PyObject): PyObject {. pyCFuncPragma .} =
  PyObject_GenericGetAttrWithDict(self, name)

proc PyObject_GenericSetAttr*(self: PyObject, nameObj: PyObject, value: PyObject): PyObject {. pyCFuncPragma .} =
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
      if not res.isPyNone:
        assert res.pyType != pyTypeErrorObjectType
        retAttributeError
    else:
      instDict[name] = value
    return pyNone
  retAttributeError

proc PyObject_GenericDelAttr*(self: PyObject, nameObj: PyObject): PyObject {. cdecl .} =
  ## EXT. CPython doesn't have `tp_delattr`
  PyObject_GenericSetAttr(self, nameObj, nil)
