## previously in Object/abstract

when defined(nimPreviewSlimSystem):
  import std/assertions

import ../../Utils/rtarrays
import ../[
  exceptions,
  stringobject,
  pybuffer,
]
import ../abstract/pybuffer
import ./[
  utils,
]
export PyBufferOrder

proc buffer_to_contiguous(mem: pointer; src: Py_buffer, order: PyBufferOrder): PyBaseErrorObject =
  ##[Copy `src` to a contiguous representation.
  Assumptions: src has `PyBUF.FULL` information, src.ndim >= 1,
   len(mem) == src.len.]##
  assert src.ndim >= 1
  assert src.shape.isNil.not
  assert src.strides.isNil.not
  
  var dest = src
  dest.buf = cast[typeof dest.buf](mem)

  var strides = initRtArray[int](src.ndim)
  dest.strides = newView(strides)

  case order
  of C, A:
    init_strides_from_shape(dest)
  else:
    init_fortran_strides_from_shape(dest)

  dest.suboffsets = default typeof dest.suboffsets

  copy_buffer(dest, src)

proc PyBuffer_ToContiguous*(buf: pointer, src: Py_buffer, len: int, order: PyBufferOrder): PyBaseErrorObject =

  if len != src.len:
    return newValueError newPyAscii("PyBuffer_ToContiguous: len != view->len");

  if src.isContiguous(order):
    copyMem(buf, src.buf, len)
    return

  # buffer_to_contiguous() assumes PyBUF_FULL
  let N = src.ndim
  var
    fb = [
      initRtArray[int](N),
      initRtArray[int](N),
      initRtArray[int](N),
    ]
  var view: Py_buffer
  view.ndim = N
  view.shape =      newView fb[0]
  view.strides =    newView fb[1]
  view.suboffsets = newView fb[2]
  
  init_shared_values(view, src)
  init_shape_strides(view, src)
  init_suboffsets(view, src)

  buffer_to_contiguous(buf, view, order)

proc PyBuffer_ToContiguous*(buf: pointer, src: Py_buffer, len: int, order: char): PyBaseErrorObject =
  assert order == 'C' or order == 'F' or order == 'A'
  PyBuffer_ToContiguous(buf, src, len, cast[PyBufferOrder](ord(order)))
