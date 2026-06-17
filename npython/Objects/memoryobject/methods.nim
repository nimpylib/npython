

import std/options
import ../[
  pyobject,
  baseBundle,
  bltcommon,
  byteobjects,
  pybuffer,
]
import ../stringobject/strformat
import ../abstract/pybuffer
import ../../Python/getargs/[dispatch, tovals]
import ./[decl, abstract]

methodMacroTmpl(MemoryView)

using self: PyMemoryViewObject
proc tobytes*(self; order = PyBufferOrder.C): PyObject =
  let L = self.view.len
  let res = newPyBytes L
  retIfExc PyBuffer_ToContiguous(res.charsView, self.view, L, order)
  res

template valErrOn(cond) {.dirty.} =
  if cond:
    return newValueError newPyAscii("order must be 'C', 'F', or 'A'")
proc tobytes*(self; order: char): PyObject =
  valErrOn order not_in ['C', 'F', 'A']
  tobytes(self, cast[PyBufferOrder](ord(order)))

proc tobytes*(self; order: Option[string]): PyObject {.clinicGenMethod(memoryview).} =
  let c = if order.isNone: 'C'
  else:
    let o = order.get()
    valErrOn o.len != 1
    o[0]
  tobytes(self, c)

