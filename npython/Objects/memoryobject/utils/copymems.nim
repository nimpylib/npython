
include ./comm
import ./equivs
when defined(js):
  import ../../charsview/memcpys
const OnlyContiguous = defined(js)
when OnlyContiguous and defined(nimPreviewSlimSystem):
  import std/assertions

template HAVE_PTR(suboffsets, dim): bool =
  ## Check for the presence of suboffsets in the first dimension. */
  suboffsets.isNil.not and (suboffsets[dim] >= 0)

template ADJUST_PTR[T](tptr: T, suboffsets, dim): T =
  ## Adjust ptr if suboffsets are present.
  if HAVE_PTR(suboffsets, dim): cast[T](cast[int](tptr) + suboffsets[dim])
  else: tptr

##  The functions in this section take a source and a destination buffer
##   with the same logical structure: format, itemsize, ndim and shape
##   are identical, with ndim > 0.
##
##   NOTE: All buffers are assumed to have PyBUF_FULL information, which
##   is the case for memoryviews!
##  Assumptions: ndim >= 1. The macro tests for a corner case that should
##   perhaps be explicitly forbidden in the PEP.

template have_Suboffsets_In_Last_Dim(view: untyped): untyped =
  (view.suboffsets.isNil.not and view.suboffsets[view.ndim - 1] >= 0)

proc last_dim_is_contiguous(dest: Py_buffer; src: Py_buffer): bool {.inline.} =
  assert(dest.ndim > 0 and src.ndim > 0)
  not have_Suboffsets_In_Last_Dim(dest) and
    not have_Suboffsets_In_Last_Dim(src) and
    dest.strides[dest.ndim - 1] == dest.itemsize and
    src.strides[src.ndim - 1] == src.itemsize

type CharsView = typeof(Py_buffer.buf)
using sptr: CharsView
when OnlyContiguous:
  using dptr: var CharsView
else:
  using dptr: CharsView
template nonContiguous(body): untyped =
  when OnlyContiguous:
    doAssert false, "only contiguous buffers are supported for this backend"
  else:
    body
when OnlyContiguous:
  type Ptr = RtArrayView[int]
else:
  type Ptr = pointer
  template `+`(x: Ptr, stride): Ptr =
    cast[Ptr](cast[int](x) + stride)
  template `+=`[P: CharsView](x: var P; i: int) =
    x = cast[P](cast[int](x) + i)
  template `[]`(x: Ptr; i: int): int8 =
    (cast[ptr int8](cast[int](x) + i))[]
const NULL = nil
proc copy_base(shape: Ptr, itemsize: int,
         dptr; dstrides, dsuboffsets: Ptr,
         sptr; sstrides, ssuboffsets: Ptr,
         mem: pointer) =
  ##[ Base case for recursive multi-dimensional copying. Contiguous arrays are
   copied with very little overhead. Assumptions: ndim == 1, mem == NULL or
   sizeof(mem) == shape[0] * itemsize. ]##
  if mem.isNil: # contiguous
    let size = shape[0] * itemsize
    template `+<`(a, size, b): bool =
      cast[int](a) + size < cast[int](b)
    if `+<`(dptr, size, sptr) or `+<`(sptr, size, dptr):
      copyMem(dptr, sptr, size) # no overlapping
    else:
      moveMem(dptr, sptr, size)
  else:
    nonContiguous:
      var p: int

      p = cast[int](mem)
      var sptr = cast[int](sptr)
      for i in 0..<shape[0]:
        let xsptr = ADJUST_PTR(sptr, ssuboffsets, 0);
        copyMem(cast[pointer](p), cast[pointer](xsptr), itemsize)
        p += itemsize
        sptr += sstrides[0]

      p = cast[int](mem)
      var dptr = cast[int](dptr)
      for i in 0..<shape[0]:
        let xdptr = ADJUST_PTR(dptr, dsuboffsets, 0);
        copyMem(cast[pointer](xdptr), cast[pointer](p), itemsize)
        p += itemsize
        dptr += dstrides[0]


proc copy_rec(shape: Ptr, ndim, itemsize: int,
         dptr; dstrides, dsuboffsets: Ptr,
         sptr; sstrides, ssuboffsets: Ptr,
         mem: pointer) =
  ##[ Recursively copy a source buffer to a destination buffer. The two buffers
   have the same ndim, shape and itemsize. ]##

  assert ndim >= 1

  if ndim == 1:
    copy_base(shape, itemsize,
                dptr, dstrides, dsuboffsets,
                sptr, sstrides, ssuboffsets,
                mem)
    return

  nonContiguous:
    var
      dptr = dptr
      sptr = sptr
    for i in 0..<shape[0]:
      let
        xdptr = ADJUST_PTR(dptr, dsuboffsets, 0)
        xsptr = ADJUST_PTR(sptr, ssuboffsets, 0)
      copy_rec(shape+1, ndim-1, itemsize,
                xdptr, dstrides+1, if dsuboffsets.isNil: dsuboffsets+1 else: NULL,
                xsptr, sstrides+1, if ssuboffsets.isNil: ssuboffsets+1 else: NULL,
                mem)
      dptr += dstrides[0]
      sptr += sstrides[0]

using
  dest: var Py_buffer
  src: Py_buffer
proc copy_buffer*(dest, src): PyBaseErrorObject =
  ##[ Recursively copy src to dest. Both buffers must have the same basic
   structure. Copying is atomic, the function never fails with a partial
   copy. ]##

  assert(dest.ndim > 0)

  retIfExc equiv_structure(dest, src)

  var mem: pointer
  when not OnlyContiguous:
    if not last_dim_is_contiguous(dest, src):
      mem = alloc(dest.shape[dest.ndim-1] * dest.itemsize)

  copy_rec(dest.shape, dest.ndim, dest.itemsize,
            dest.buf, dest.strides, dest.suboffsets,
            src.buf, src.strides, src.suboffsets,
            mem)
  when not OnlyContiguous:
    dealloc mem
