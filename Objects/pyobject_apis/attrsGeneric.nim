
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


proc PyObject_GenericGetAttrWithDict*(self: PyObject; name: PyStrObject|PyObject,
    typeDict: PyDictObject = self.getTypeDict, supress: static[bool] = false): PyObject =
  ## returns nil if supress and not found
  nameAsStr
  if typeDict.isNil:
    unreachable("for type object dict must not be nil")
  when supress:
    template SupressAE = return nil
  var descr: PyObject
  typeDict.withValue(name, value):
    descr = value[]
    let descrGet = descr.pyType.magicMethods.get
    if not descrGet.isNil:
      result = descr.descrGet(self)
      when supress:
        if result.isExceptionOf Attribute:
          SupressAE
      else: return 

  if self.hasDict:
    let instDict = PyDictObject(self.getDict)
    instDict.withValue(name, val):
      return val[]

  if not descr.isNil:
    return descr

  when supress: SupressAE
  else: return newAttributeError(self, name)

proc PyObject_GenericGetAttrWithDict*(self: PyObject; name: PyStrObject|PyObject,
    typeDict: typeof(nil), supress: static[bool] = false): PyObject =
  PyObject_GenericGetAttrWithDict(self, name, supress=supress)

proc PyObject_GenericGetAttr*(self: PyObject, name: PyObject): PyObject {. cdecl .} =
  PyObject_GenericGetAttrWithDict(self, name)

proc PyObject_GenericSetAttr*(self: PyObject, nameObj: PyObject, value: PyObject): PyObject {. cdecl .} =
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
