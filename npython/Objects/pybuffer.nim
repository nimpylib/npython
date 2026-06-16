

import ./[
  pyobject,
  exceptions,
  byteobjects,
]
export rtarrays

const PyBUF_MAX_NDIM* = 64

template `or`(a, b): untyped = a.ord or b.ord
type
  PyBUF*{.pure.} = enum
    Simple = 0
    Writable = 1

    Format = 4
    Nd = 8
    Strides = 0x10 or Nd
    C_Contiguous = 0x20 or Strides
    F_Contiguous = 0x40 or Strides
    Indirect = 0x80 or Strides

    Contig = Nd or Writable

    Strided = Strides or Writable

    Records = Strides or Writable or Format
    RecordsRO = Strides or Format

    Full = Indirect or Writable or Format
    FullRO = Indirect or Format


    READ = 0x100
    WRITE = 0x200

const
  PyBUF_ContigRO* = PyBUF.Nd
  PyBUF_StridedRO* = PyBUF.Strides

type Py_buffer* = object
  buf*: CharsView
  obj*: PyObject
  len*: int
  itemsize*: int
  readonly*: bool
  ndim*: int
  format*: cstring
  shape*, strides*, suboffsets*: RtArrayView[int]
  privateInternal*: PyObject  # unstable

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
