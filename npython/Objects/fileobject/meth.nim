
include ./comm
import ./decl
import ../bltcommon
import ../[pyobject, exceptions, noneobject, stringobject, byteobjects,]
import ../numobjects/intobject

import ../exceptions/ioerror
import ../../Python/getargs/dispatch

methodMacroTmpl(File)

template genEncodingIO(def): untyped = clinicGenMethodRaises(File, [IOError, ValueError, LookupError, OSError], def)

proc read*(self: PyFileObject): PyObject {.genEncodingIO.} =
  if self.io of pyio.NoEncTextIOWrapper:
    return newPyStr(pyio.NoEncTextIOWrapper(self.io).read())
  newPyBytes(@(pyio.RawIOBase(self.io).read()))

proc write*(self: PyFileObject, value: PyObject): PyObject {.genEncodingIO.} =
  if self.io of pyio.NoEncTextIOWrapper:
    return newPyInt(pyio.NoEncTextIOWrapper(self.io).write(PyStrObject(value).asUTF8))
  let items = PyBytesObject(value).items
  newPyInt(pyio.RawIOBase(self.io).write(items.toOpenArray(0, items.high)))

proc close*(self: PyFileObject) {.clinicGenMethod(File).} =
  self.io.close()

proc readline*(self: PyFileObject): PyObject {.genEncodingIO.} =
  if self.io of pyio.NoEncTextIOWrapper:
    return newPyStr(pyio.NoEncTextIOWrapper(self.io).readline())
  newPyBytes(@(pyio.RawIOBase(self.io).readline()))

proc next*(self: PyFileObject): PyObject =
  result = readline(self)
  if (result.ofPyStrObject and PyStrObject(result).str.len == 0) or
      (result.ofPyBytesObject and PyBytesObject(result).items.len == 0):
    return newStopIterError()

implFileMagic iter: self
implFileMagic iternext:
  withNimErrorsAsPy [IOError, ValueError, LookupError, OSError]:
    next(self)
