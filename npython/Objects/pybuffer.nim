
import ../Utils/trans_imp
impExpCwd pybuffer, [decl]

import ./[
  pyobject, exceptions,
  byteobjects,
]
import ./byteobjects/utils

proc toval*(o: PyObject, val: var Py_buffer): PyBaseErrorObject =
  let c = o.PyNumber_AsCharOr("bytes") do:
    if o.ofPyBytesObject:
      let ob = o.PyBytesObject
      val = init_Py_buffer ob
      return
    elif o.ofPyByteArrayObject:
      let ob = o.PyByteArrayObject
      val = init_Py_buffer ob
      return
    else:
      # TODO:buffer
      return bufferNotImpl()
    # return self.doSth s
  let obj = newPyBytes [c]
  val = init_Py_buffer obj

