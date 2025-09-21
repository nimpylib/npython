

import ./helpers
import ../[
  pyobject,
]
proc PyObject_GetItem*(o: PyObject; key: PyObject): PyObject =
  if o.isNil or key.isNil:
    return null_error()
  let f = o.getMagic(getitem)
  if not f.isNil:
    return f(o, key)
  #TODO:class_getitem
  #[
  if o.ofPyTypeObject:
    let tp = PyTypeObject(o)
    if tp == pyTypeObjectType:
      return 
    ]#
  type_errorn("'$#' object is not subscriptable", o)

proc PyObject_SetItem*(o: PyObject; key, value: PyObject): PyObject =
  if o.isNil or key.isNil or value.isNil:
    return null_error()
  let f = o.getMagic(setitem)
  if not f.isNil:
    return f(o, key, value)
  type_errorn("'$#' object does not support item assignment", o)
