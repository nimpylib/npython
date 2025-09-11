
import ../[
  pyobject,
  exceptions,
  stringobject,
]

import ../numobjects/intobject/[decl, ops_imp_warn]

proc has_sq_length*(o: PyObject): bool =
  #TODO:mro
  not o.getMagic(len).isNil

proc sq_length*(o: PyObject, resi: var int): PyBaseErrorObject =
  ## typeobject.c:slot_sq_length
  
  template ret(e: PyBaseErrorObject) =
    return e
  #TODO:mro vectorcall_method
  let mlen = o.getMagic(len)
  if mlen.isNil:
    ret newTypeError newPyAscii"no __len__ found" #TODO: dive vectorcall_method's errmsg
    # this msg is just what I made at random
  var resObj = mlen(o)
  retIfExc resObj
  resObj = privatePyNumber_Index(resObj)
  retIfExc resObj
  assert resObj.ofPyIntObject
  let res = PyIntObject resObj
  if res.negative:
    return newValueError newPyAscii"__len__() should return >= 0"
  result = PyLong_AsSsize_t(res, resi)
  assert resi >= 0 or result.ofPyOverflowErrorObject


proc has_sq_item*(self: PyObject): bool = not self.getMagic(getitem).isNil
proc sq_item*(self: PyObject, i: int): PyObject =
  ## slot_sq_item
  let ival = newPyInt(i)
  #TODO: vectorcall_method(&_Py_ID(__getitem__), stack, 2);
  self.getMagic(getitem)(self, ival)
