import pyobject
import baseBundle


# read only dict used for `__dict__` of types
declarePyType DictProxy():
  dict: PyObject

implDictProxyMagic repr:
  # todo: add "dictproxy" or "mappingproxy" after string methods are implemented
  self.dict.callMagic(repr)

implDictProxyMagic str:
  self.dict.callMagic(str)

implDictProxyMagic getitem:
  self.dict.callMagic(getitem, other)

implDictProxyMagic len:
  self.dict.callMagic(len)

implDictProxyMagic init(mapping: PyObject):
  self.dict = mapping
  pyNone

proc newPyDictProxy*(mapping: PyObject): PyObject {. cdecl .} =
  let d = newPyDictProxySimple()
  d.dict = mapping
  d
  
