
import ../../Python/call
import ../../Include/internal/pycore_global_strings
import ../[
  pyobject,
  exceptions,
  stringobject,
]
import ../numobjects/intobject
import ../typeobject/apis/attrs
import ../pyobject_apis/strings
import ../stringobject/strformat


proc PyObject_Format*(obj: PyObject, format_spec: PyObject): PyObject =
  var meth: PyObject

  if format_spec != nil and not format_spec.ofPyStrObject:
        return newSystemError newPyStr(
          &"Format specifier must be a string, not {format_spec.typeName:.200s}")

  var format_spec = PyStrObject(format_spec)
  # Fast path for common types.
  if format_spec.isNil or format_spec.len == 0:
      if (ofExactPyStrObject(obj)):
          return obj
      if (ofExactPyIntObject(obj)):
          return PyObject_Str(obj)

  # If no format_spec is provided, use an empty string
  if format_spec.isNil:
    format_spec = newPyAscii()

  # Find the (unbound!) __format__ method
  meth = PyObject_LookupSpecial(obj, pyDUId(format))
  if meth.isNil:
    return newTypeError newPyStr &"Type {obj.typeName:.100s} doesn't define __format__"
  retIfExc meth

  # And call it.
  result = call(meth, format_spec);

  if not result.isThrownException and not result.ofPyStrObject:
      return newTypeError newPyStr(
        &"{obj.typeName}.__format__() must return a str, not {result.typeName}",
      )
