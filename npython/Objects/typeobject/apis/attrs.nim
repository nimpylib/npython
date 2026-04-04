
import ../../[
  pyobject, stringobject,
]
import ../../pyobject_apis/attrsGeneric
export PyType_LookupStackRefAndVersion

using typ: PyTypeObject
using name: PyStrObject

proc PyType_LookupRefAndVersion*(typ; name: PyStrObject, version: var uint): PyObject =
    ##[ `_PyType_LookupRefAndVersion`
    Internal API to look for a name through the MRO.
   This returns a strong reference, and doesn't set an exception!
   If nonzero, version is set to the value of type->tp_version at the time of
   the lookup.]##
    var o: PyStackRef
    version = PyType_LookupStackRefAndVersion(typ, name, o)
    if o.isNull:
      return nil
    return o.asPyObjectSteal

proc PyType_LookupRefAndVersion*(typ; name: PyStrObject): PyObject =
  ## `_PyType_LookupRefAndVersion(typ, name, NULL)`
  var version: uint
  PyType_LookupRefAndVersion(typ, name, version)

proc PyType_LookupRef*(typ; name): PyObject =
  ##[ `_PyType_LookupRef`
  Internal API to look for a name through the MRO.
   This returns a strong reference, and doesn't set an exception!]##
  PyType_LookupRefAndVersion(typ, name)


proc PyObject_LookupSpecial*(self: PyObject, attr: PyStrObject): PyObject =
  ##[ `_PyObject_LookupSpecial`

  Routines to do a method lookup in the type without looking in the
   instance dictionary (so we can't use PyObject_GetAttr) but still
   binding it to the instance.

   Variants:

   - _PyObject_LookupSpecial() returns NULL without raising an exception
     when the _PyType_LookupRef() call fails;

   - lookup_maybe_method() and lookup_method() are internal routines similar
     to _PyObject_LookupSpecial(), but can return unbound PyFunction
     to avoid temporary method object. Pass self as first argument when
     unbound == 1.
  ]##
  result = PyType_LookupRef(self.pyType, attr)

  #XXX: do not use: retIfExc result
  # as may return nil over exception
  if result.isNil: return

  let descrGet = result.getMagic(get)
  if not descrGet.isNil:
    result = descrGet(result, self)
