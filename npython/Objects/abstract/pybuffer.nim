
import pkg/handy_sugars/trans_imp
import ../[
  pyobject,
  exceptions,
  pybuffer,
]
import ../memoryobject/[decl, status,]
import ../stringobject/strformat

import ../../Include/cpython/pyerrors
export PyBufferFlags

import ./pybuffer/[helpers,]
requireRawMemorySupport:
  impExpCwd pybuffer, [
    get, release,
  ]
impExpCwd pybuffer, [
  contiguous, utils,
]

func contains(a: PyBufferFlags, b: PyBuf): bool =
  (a.ord and b.ord) == b.ord

const NULL = default typeof Py_buffer.shape
proc PyBuffer_FillInfo*(view: var Py_buffer, obj: PyObject,
  buf: pointer, len: int, readonly: bool, flags = PyBufferFlags PyBuf.Simple
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
  view.buf = cast[typeof view.buf](buf)
  view.len = len
  view.readonly = readonly
  view.itemsize = 1
  view.format = nil
  if flags.contains PyBUF.FORMAT:
    view.format = "B"
  view.ndim = 1
  view.shape = NULL
  if flags.contains PyBUF.ND:
    view.shape = newRtArrayView(addr view.len)
  view.strides = NULL
  if flags.contains PyBUF.STRIDES:
    view.strides = newRtArrayView(addr view.itemsize)
  view.suboffsets = NULL
  #view.internal = nil

