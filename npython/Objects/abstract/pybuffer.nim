
import pkg/handy_sugars/trans_imp
import ../[
  pyobject,
  exceptions,
  pybuffer,
]
import ../memoryobject/[decl,]
import ../stringobject/strformat

import ../../Include/cpython/pyerrors
export PyBufferFlags

import ./pybuffer/[helpers,]
import ../charsview/decl
impExpCwd pybuffer, [
  get, release,
]
impExpCwd pybuffer, [
  contiguous, utils,
]

func contains(a: PyBufferFlags, b: PyBuf): bool =
  (a.ord and b.ord) == b.ord

const NULL = default typeof Py_buffer.shape
genCharsViewDecl Ptr
proc PyBuffer_FillInfo*(view: var Py_buffer, obj: PyObject,
  buf: Ptr; len: int, readonly: bool, flags = PyBufferFlags PyBuf.Simple
): PyBaseErrorObject =
  #[
  if view.isNil:
      return newBufferError newPyAscii(
        "PyBuffer_FillInfo: view==NULL argument is obsolete")
  ]#
  checkFlags flags:
    if (flags.contains PyBUF.WRITABLE) and readonly:
      return newBufferError newPyAscii"Object is not writable."

  view.obj = obj
  view.buf = buf
  view.len = len
  view.readonly = readonly
  view.itemsize = 1
  view.format = nil
  if flags.contains PyBUF.FORMAT:
    view.format = "B"
  view.ndim = 1
  view.shape = NULL
  template newViewFrom(x: int): untyped =
    when defined(js):
      newView initRtArray[int] [x]
    else:
      newRtArrayView(addr x)
  if flags.contains PyBUF.ND:
    view.shape = newViewFrom(view.len)
  view.strides = NULL
  if flags.contains PyBUF.STRIDES:
    view.strides = newViewFrom(view.itemsize)
  view.suboffsets = NULL
  #view.internal = nil

