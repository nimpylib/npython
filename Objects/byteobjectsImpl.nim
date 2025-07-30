
import std/strformat

import ./byteobjects
import ./pyobject
import ./[boolobject, numobjects, stringobject, exceptions, noneobject,
  iterobject,
]


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
  `impl B Magic` hash: newPyInt self.hash
  `impl B Magic` iter, mutRead:
    genPyNimIteratorIter self.ints


impl Bytes, []
impl ByteArray, [mutable: read]

template impl(x, fromSize, fromObject) =
  if x.ofPyStrObject:
    return newTypeError newPyAscii"string argument without an encoding"
  # Is it an integer?
  let fun = x.getMagic(index)
  if not fun.isNil:
    var size: int
    result = PyNumber_AsSsize_t(x, size)
    if size == -1 and result.isThrownException:
      if not result.isExceptionOf ExceptionToken.Type:
        return  # OverflowError
      fromObject x
    else:
      if size < 0:
        return newValueError newPyAscii"negative count"
      fromSize size
  else:
    fromObject x

# TODO: encoding, errors params
implBytesMagic New(tp: PyObject, x: PyObject):
  var bytes: PyObject
  let fun = x.getMagic(bytes)
  if not fun.isNil:
    result = fun(x)
    if not result.ofPyBytesObject:
      return newTypeError newPyString(
        &"__bytes__ returned non-bytes (type {result.pyType.name:.200s})")
    return

  template fromSize(size) = bytes = newPyBytes size
  template fromObject(o) = bytes = PyBytes_FromObject o
  impl x, fromSize, fromObject
  return bytes


# TODO: encoding, errors params
implByteArrayMagic init:
  if args.len == 0:
    return pyNone
  checkArgNum 1  # TODO
  let x = args[0]
  if self.items.len != 0:
    self.items.setLen(0)

  template fromSize(size) = self.setLen size
  template fromObject(o) =
    let e = self.initFromObject o
    if not e.isNil: return e
  impl x, fromSize, fromObject
  pyNone
