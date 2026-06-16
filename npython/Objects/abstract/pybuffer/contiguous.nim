
import ../../[
  pybuffer,
]

using view: Py_buffer
proc isFortranContiguous*(view): bool =
  ## `_IsFortranContiguous`

  #[ 1) len = product(shape) * itemsize
      2) itemsize > 0
      3) len = 0 <==> exists i: shape[i] = 0 ]#
  if view.len == 0: return true
  if view.strides.isNil: # C-contiguous by definition
    # Trivially F-contiguous
    if view.ndim <= 1: return true

    # ndim > 1 implies shape != NULL
    assert(view.shape.isNil.not)

    # Effectively 1-d
    var sd = 0;
    for i in 0..<view.ndim:
      if view.shape[i] > 1: sd += 1
    return sd <= 1

  # strides != NULL implies both of these
  assert(view.ndim > 0)
  assert(view.shape.isNil.not)

  var sd = view.itemsize
  for i in 0..<view.ndim:
    let dim = view.shape[i]
    if dim > 1 and view.strides[i] != sd:
      return false
    sd *= dim
  return true

proc isCContiguous*(view): bool =
  #[ 1) len = product(shape) * itemsize
      2) itemsize > 0
      3) len = 0 <==> exists i: shape[i] = 0 ]#
  if view.len == 0: return true
  if view.strides.isNil: return true # C-contiguous by definition

  # strides != NULL implies both of these
  assert(view.ndim > 0)
  assert(view.shape.isNil.not)

  var sd = view.itemsize
  for i in countdown(view.ndim-1, 0):
    let dim = view.shape[i]
    if dim > 1 and view.strides[i] != sd:
      return false
    sd *= dim
  return true


type PyBufferOrder*{.pure.} = enum
  C = 'C'
  F = 'F'
  A = 'A'

# Objects/abstract.c
proc isContiguous*(view; order: PyBufferOrder): bool =
  ## `PyBuffer_IsContiguous`
  if view.suboffsets.isNil.not:
    return false
  case order
  of C: view.isCContiguous
  of F: view.isFortranContiguous
  of A: view.isCContiguous or view.isFortranContiguous

proc isContiguous*(view; order: char): bool =
  if order not_in ['C', 'F', 'A']:
    return false #XXX:BAD-PY: cpython returns false here
  isContiguous(view, cast[PyBufferOrder](ord(order)))
