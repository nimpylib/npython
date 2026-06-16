
import std/with
import ../[
  pyobject,
  baseBundle,
  bltcommon,
  pybuffer,
  tupleobject,
]
import ../stringobject/strformat
import ../abstract/pybuffer/[get, utils,]
import ./[decl, utils,]


proc newPyManagedBuffer*(view: Py_buffer): PyManagedBufferObject =
  result = newPyManagedBufferSimple()
  result.master = view

proc newPyManagedBuffer*(base: PyObject, flags: PyBufferFlags): PyObject =
  ## `_PyManagedBuffer_FromObject`
  let mbuf = newPyManagedBufferSimple()
  retIfExc PyObject_GetBuffer(base, mbuf.master, flags)
  result = mbuf

proc newPyMemoryViewOfDim(ndim: int): PyMemoryViewObject =
  ## `memory_alloc`
  ## 
  result = newPyMemoryViewSimple()
  result.mbuf = nil
  result.hash = Hash -1

  template asgn(attr) {.dirty.} =
    result.attr = initRtArray[int](ndim)
    result.view.attr = newView result.attr
  asgn shape
  asgn strides
  asgn suboffsets

  result.view.ndim = ndim

proc mbuf_add_view(mbuf: PyManagedBufferObject, src: var Py_buffer = mbuf.master): PyObject{.raises: [].} =
  ## `mbuf_add_view`
  
  if src.ndim > PyBUF_MAX_NDIM:
    return newValueError newPyAscii(
              "memoryview: number of dimensions must not exceed " & $PyBUF_MAX_NDIM
    )

  let mv: PyMemoryViewObject = newPyMemoryViewOfDim src.ndim

  with mv.view:
    init_shared_values src
    init_shape_strides src
    init_suboffsets src
  
  init_flags mv
  mv.mbuf = mbuf

  inc mbuf.exports

  return mv
proc newPyMemoryView*(view: Py_buffer): PyObject =
  ## `PyMemoryView_FromBuffer`
  let mbuf = newPyManagedBuffer view
  mbuf_add_view(mbuf)

proc newPyMemoryView*(v: PyObject; flags: PyBufferFlags): PyObject =
  ## `PyMemoryView_FromObjectAndFlags`
  if v.ofPyMemoryViewObject:
    let mv = PyMemoryViewObject v
    CHECK_RELEASED mv
    CHECK_RESTRICTED mv
    return mbuf_add_view(mv.mbuf)
  elif v.ofPyBuffer:
    let mbuf = newPyManagedBuffer(v, flags)
    retIfExc mbuf
    return mbuf_add_view(PyManagedBufferObject mbuf)
  else:
    return newTypeError newPyStrF"memoryview: a bytes-like object is required, not '{v.typeName:.200s}'"

proc newPyMemoryView*(obj: PyObject): PyObject =
  ## `PyMemoryView_FromObject`
  newPyMemoryView obj, PyBufferFlags(PyBUF.FULL_RO)

methodMacroTmpl(memoryview)

implMemoryViewMagic New(_, obj): newPyMemoryView(obj)
