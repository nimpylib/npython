

import ../[
  pybuffer,
]
import ../abstract/pybuffer/[arithptr, contiguous,]

import ../../Utils/[rtarrays, trans_imp,]

impExpCwd utils, [
  equivs, copymems,
]
import ./decl

using
  dest: var Py_buffer
  src: Py_buffer
using view: var Py_buffer
{.push inline.}
proc init_shared_values*(dest; src) =
  template copyA(attr) {.dirty.} =
    dest.attr = src.attr
  copyA obj
  copyA buf
  copyA len
  copyA itemsize
  copyA readonly
  if src.format.isNil:
    dest.format = cstring"B"
  else:
    copyA format

proc init_strides_from_shape*(dest) =
  let n = dest.ndim
  assert n > 0

  dest.strides[n-1] = dest.itemsize
  for i in countdown(n-2, 0):
    dest.strides[i] = dest.strides[i+1] * dest.shape[i+1]

proc init_fortran_strides_from_shape*(view) =
  assert(view.ndim > 0)

  view.strides[0] = view.itemsize
  for i in 1..<view.ndim:
    view.strides[i] = view.strides[i-1] * view.shape[i-1]

proc init_shape_strides*(dest; src) =
  template NULL: untyped = default typeof dest.shape
  if src.ndim == 0:
    dest.shape = NULL
    dest.strides = NULL
    return
  if src.ndim == 1:
    dest.shape[0] = if src.shape.isNil: src.len div src.itemsize else: src.shape[0]
    dest.strides[0] = if src.strides.isNil: src.itemsize else: src.strides[0]
    return

  for i in 0..<src.ndim:
    dest.shape[i] = src.shape[i]
  if src.strides.isNil.not:
    for i in 0..<src.ndim:
      dest.strides[i] = src.strides[i]
  else:
    init_strides_from_shape(dest)

proc init_suboffsets*(dest; src) =
  if src.suboffsets.isNil:
    dest.suboffsets = default typeof dest.suboffsets
    return
  for i in 0..<src.ndim:
    dest.suboffsets[i] = src.suboffsets[i]
{.pop.}

using mv: PyMemoryViewObject
proc contiguousNDim1(view: Py_buffer): bool =
  ## `MV_CONTIGUOUS_NDIM1`
  ## 
  ## Fast contiguity test. Caller must ensure suboffsets==NULL and ndim==1.
  if view.ndim != 1:
    return false
  assert not view.strides.isNil
  return view.strides[0] == view.itemsize



proc init_flags*(mv) =
  template view: untyped = mv.view
  var flags: IntFlag[PyMemoryViewFlags]
  let isContig = view.suboffsets.isNil
  case view.ndim:
  of 0:
    flags = PyMemoryViewFlags.SCALAR or PyMemoryViewFlags.C or PyMemoryViewFlags.FORTRAN
  of 1:
    if view.contiguousNDim1:
      flags = PyMemoryViewFlags.C or PyMemoryViewFlags.FORTRAN
  elif isContig:
    if view.isCContiguous():
      flags = PyMemoryViewFlags.C
    elif view.isFortranContiguous():
      flags = PyMemoryViewFlags.FORTRAN
  
  if not isContig:
    flags = flags or PyMemoryViewFlags.PIL
    flags = IntFlag[PyMemoryViewFlags](
      flags.ord and not(PyMemoryViewFlags.C or PyMemoryViewFlags.FORTRAN).ord
    )

  mv.flags = flags
