
import std/strformat

import ./byteobjects
import ./pyobject
import ./[boolobject, numobjects, stringobject, exceptions]


export byteobjects


template impl(B, mutRead){.dirty.} =
  methodMacroTmpl(B)
  type `T B` = `Py B Object`
  `impl B Magic` eq:
    if not other.`ofPy B Object`:
      return pyFalseObj
    return newPyBool self == `T B`(other)
  `impl B Magic` len, mutRead: newPyInt self.len
  `impl B Magic` repr, mutRead: newPyAscii(repr self)
  `impl B Magic` hash: newPyInt self.items


impl Bytes, []
impl ByteArray, [mutable: read]

# TODO: encoding, errors params
implBytesMagic New(tp: PyObject, x: PyObject):
  var bytes: PyObject
  var fun: UnaryMethod
  fun = x.getMagic(bytes)
  if not fun.isNil:
    result = fun(x)
    if not result.ofPyBytesObject:
      return newTypeError newPyString(
        &"__bytes__ returned non-bytes (type {result.pyType.name:.200s})")
    return
  
  if x.ofPyStrObject:
    return newTypeError newPyAscii"string argument without an encoding"
  # Is it an integer?
  fun = x.getMagic(index)
  if not fun.isNil:
    var size: int
    result = PyNumber_AsSsize_t(x, size)
    if size == -1 and result.isThrownException:
      if not result.isExceptionOf Type:
        return  # OverflowError
      bytes = PyBytes_FromObject x
    else:
      if size < 0:
        return newValueError newPyAscii"negative count"
      bytes = newPyBytes size
  else:
    bytes = PyBytes_FromObject x
  return bytes

