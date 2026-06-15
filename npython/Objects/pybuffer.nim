

import ./[
  pyobject,
  exceptions,
  byteobjects,
]
import ../Utils/[destroyPatch,]

#TODO:buffer
# workaround:
type Py_buffer* = object
  buf*: CharsView
  len*: int
  obj*: PyObject
defdestroy Py_buffer: discard
#proc PyBuffer_Release(b: Py_buffer) = discard

proc init_Py_buffer*(buf: CharsView, len: int, obj: PyObject, ): Py_buffer = Py_buffer(buf: buf, len: len, obj: obj)

proc to_py_buffer*(b: PyBytesObject|PyByteArrayObject): CharsView = b.charsView

proc init_Py_buffer*(buf: PyBytesObject|PyByteArrayObject): Py_buffer{.raises: [].} =
  init_Py_buffer(buf.to_py_buffer, buf.len, buf)


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
