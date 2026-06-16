import ../[
  pyobject,
  baseBundle,
  pybuffer,
  tupleobject,
]
import ../stringobject/strformat
import ../abstract/pybuffer/arithptr
import ../../Utils/intflags
export intflags

prepareIntFlagOr
declareIntFlag PyMemoryViewFlags:
    RELEASED    0x001
    C           0x002
    FORTRAN     0x004
    SCALAR      0x008
    PIL         0x010
    RESTRICTED  0x020
type PyBufferFlags* = IntFlag[PyMemoryViewFlags|PyBUF]

declareIntFlag PyManagedBufferFlags:
  RELEASED    0x001
  FREE_FORMAT 0x002  # need to free format string (self.master.format) in mbuf_dealloc

declarePyType ManagedBuffer():
  exports: int  # refcount
  master: Py_buffer
  ndim: int
  flags: IntFlag[PyManagedBufferFlags]

declarePyType MemoryView():
  mbuf: PyManagedBufferObject
  hash: Hash  # for read-only ones
  flags: IntFlag[PyMemoryViewFlags]
  exports: int  # refcount of views created from this view
  view: Py_buffer
  # following are of length of view.ndim
  shape:      RtArray[int]
  strides:    RtArray[int]
  suboffsets: RtArray[int]

using mv: PyMemoryViewObject
proc BASE_INACCESSIBLE*(mv): bool {.inline.} =
  const R = PyMemoryViewFlags.RELEASED
  (mv.flags & R) or
   (mv.mbuf.flags & R)

template CHECK_RELEASED*(mv) =
  if BASE_INACCESSIBLE(mv):
    return newValueError newPyAscii("operation forbidden on released memoryview object")

template CHECK_RESTRICTED*(mv) =
  if mv.flags & PyMemoryViewFlags.RESTRICTED:
    return newValueError newPyAscii("cannot create new view on restricted memoryview")

{.push inline.}
template `&`(a, b: IntFlag[PyMemoryViewFlags]): bool = (a.ord and b.ord) != 0
using flags: IntFlag[PyMemoryViewFlags]
proc c_contiguous*(flags): bool = flags & (PyMemoryViewFlags.SCALAR|PyMemoryViewFlags.C) ## `MV_C_CONTIGUOUS`
proc f_contiguous*(flags): bool = flags & (PyMemoryViewFlags.SCALAR|PyMemoryViewFlags.FORTRAN) ## `MV_F_CONTIGUOUS`
proc anyContiguous*(flags): bool =
  ## `MV_ANY_CONTIGUOUS`
  flags & (PyMemoryViewFlags.SCALAR|PyMemoryViewFlags.C|PyMemoryViewFlags.FORTRAN)
{.pop.}

using self: PyMemoryViewObject
proc obj*(self): PyObject =
  let view = self.view
  CHECK_RELEASED self
  if view.obj.isNil:
    return pyNone
  view.obj
genProperty memoryview, "obj", obj, self.obj

template genTo(name, res) {.dirty.} =
  proc name*(self): PyObject =
    CHECK_RELEASED self
    res
  genProperty memoryview, astToStr(name), name, name(self)

proc IntTuple(len: int, vals: typeof(PyMemoryViewObject.view.shape)): PyTupleObject =
  ## `_IntTupleFromSsizet`
  if vals.isNil: return newPyTuple()
  PyTuple_Collect:
    for i in 0..<len:
      newPyInt vals[i]

genTo nbytes:   newPyInt self.view.len
genTo format:   newPyStr self.view.format
genTo itemsize: newPyInt self.view.itemsize
genTo shape:     IntTuple self.view.ndim, self.view.shape
genTo strides:   IntTuple self.view.ndim, self.view.strides
genTo suboffsets:IntTuple self.view.ndim, self.view.suboffsets
genTo readonly:  newPyBool self.view.readonly
genTo ndim:      newPyInt self.view.ndim
genTo c_contiguous: newPyBool cContiguous self.flags
genTo f_contiguous: newPyBool fContiguous self.flags
genTo contiguous:   newPyBool anyContiguous self.flags

proc repr*(self): string {.raises: [].} =
  if self.flags & PyMemoryViewFlags.RELEASED:
    fmt"<released memory at {self.idStr}>"
  else:
    fmt"<memory at {self.idStr}>"
method `$`*(self): string {.raises: [].} = repr self
implMemoryViewMagic repr: newPyAscii $self

proc len*(self): int =
  if self.view.ndim == 0:
    raise newException(ValueError, "0-dim memory has no length")
  self.view.shape[0]
implMemoryViewMagic len:
  newPyInt(
    try: self.len
    except ValueError as e: return newTypeError newPyAscii e.msg
  )
