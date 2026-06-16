
import ../../[
  pyobject,
  exceptions,
  pybuffer,
]
import ../../memoryobject/[constructors,]

proc PyBuffer_Release*(view: var Py_buffer): PyBaseErrorObject =
  ## `PyBuffer_Release`
  let o = view.obj
  if o.isNil: return
  let tp = o.pyType
  if tp.isNil: return
  let pb = tp.magicMethods.release_buffer
  if pb.isNil: return

  retIfExc pb(o, newPyMemoryView(view))
