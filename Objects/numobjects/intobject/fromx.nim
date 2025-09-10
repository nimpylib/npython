

import ./[decl, ops]
import ../[numobjects_comm, helpers]
import ../../stringobject/strformat
import ../../../Modules/unicodedata/decimalAndSpace
include ./bytes_h

template PyLong_FromBytesImpl(buffer: openArray[char]; base = 10) =
  var nParsed: int
  result = PyLong_FromString(buffer, nParsed, base)
  if nParsed == buffer.len:
    return result

proc PyLong_FromBytes*(buffer: openArray[char]; base = 10): PyObject =
  PyLong_FromBytesImpl(buffer, base)
  let bObj = newPyBytes @buffer
  retInvIntCall bObj, base

proc PyLong_FromUnicodeObject*(u: PyStrObject, base = 10): PyObject =
  let asciidigObj = PyUnicode_TransformDecimalAndSpaceToASCII(u)
  retIfExc asciidigObj
  let asciidig = PyStrObject asciidigObj
  assert asciidig.isAscii
  # Simply get a pointer to existing ASCII characters.
  let buffer = asciidig.asUTF8

  PyLong_FromBytesImpl(buffer, base)
  retIfExc result

  retInvIntCall u, base

proc PyNumber_Long*(o: PyObject; resi: var PyIntObject): PyBaseErrorObject{.pyCFuncPragma.} =
  PyNumber_FloatOrIntImpl(o, resi, int):
    ret res

  template retMayE(e: PyObject) =
    let res = e
    retIfExc e
    ret res
  if o.ofPyStrObject:
    # The below check is done in PyLong_FromUnicodeObject().
    retMayE PyLong_FromUnicodeObject(PyStrObject o)
  if o.ofPyBytesObject:
    #[need to do extra error checking that PyLong_FromString()
      doesn't do.  In particular int('9\x005') must raise an
      exception, not truncate at the null.]#
    let b = PyBytesObject o
    retMayE PyLong_FromBytes(b.items)
  if o.ofPyByteArrayObject:
    let b = PyByteArrayObject o
    retMayE PyLong_FromBytes(b.items)
  #TODO:buffer
  let s = newPyStr&("int() argument must be a string, a bytes-like object "&
                      "or a real number, not '{o.typeName:.200s}'")
  retIfExc s
  return newTypeError PyStrObject s

genNumberVariant Long, int

