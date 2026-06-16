
import ../../[
  pyobject,
  exceptions,
  pybuffer,
]


import ../../memoryobject/decl
import ../../numobjects/intobject
import ../../stringobject/strformat

import ../../../Include/cpython/pyerrors
import ./helpers

template invokeGetBuffer(pb; o, view, flags) =
  ## `PyBufferProcs.bf_getbuffer`
  
  let viewObj = pb(o, newPyInt flags.ord)
  retIfExc viewObj

  let mv = PyMemoryViewObject(viewObj)
  view = mv.view
  view.obj = o
  view.privateInternal = mv  # ensure the \
  #  .shape/.strides/.suboffsets will point to alive references

proc PyObject_GetBuffer*(obj: PyObject, view: var Py_buffer, flags: PyBufferFlags): PyBaseErrorObject =
  checkFlags flags: discard
  let pb = obj.getMagic(buffer);

  if pb.isNil:
    return newTypeError newPyStrF"a bytes-like object is required, not '{obj.typeName:.100s}'"
  invokeGetBuffer(pb, obj, view, flags)
  #assert(_Py_CheckSlotResult(obj, "getbuffer", res >= 0));

proc PyObject_GetBuffer*(obj: PyObject, view: var Py_buffer, flags: PyBUF|PyMemoryViewFlags): PyBaseErrorObject =
  PyObject_GetBuffer(obj, view, PyBufferFlags(flags.ord))

