
import std/strformat
import ../[
  pyobjectBase,
  stringobject,
  exceptions,
]
import ../abstract/sequence/list
import ../../Utils/rtarrays

template bytes_join*(S; sep; iterable: PyObject; mutable: bool)#[: PyObject]#{.dirty.} =
  bind RtArray, initRtArray
  bind PySequence_Fast, PySequence_Fast_GET_SIZE, PySequence_Fast_GET_ITEM
  bind newPyStr, newPyAscii, newRuntimeError, newTypeError, newOverflowError
  bind formatValue, fmt
  let
    sepstr = sep.charsView
    seplen = len(sep)

  let sequ = PySequence_Fast(iterable, "can only join an iterable")
  retIfExc sequ

  let seqlen = PySequence_Fast_GET_SIZE(sequ)
  if seqlen == 0:
    return `newPy S`()

  var item: PyObject
  when not mutable:
    if seqlen == 1:
      item = PySequence_Fast_GET_ITEM(sequ, 0)
      if item.`ofExactPy S Object`:
        return item

  const GIL_THRESHOLD = 1048576

  #XXX: NIM-BUG: when JS using RtArray: `Error: internal error: ("genAddr: 2", skTemp)`
  # due to `[]=` or `[]` to RtArray
  var buffers = (when defined(js): newSeq else: initRTArray)[Py_buffer](seqlen)


  #[ Here is the general case.  Do a pre-pass to figure out the total
    amount of space we'll need (sz), and see whether all arguments are
    bytes-like.
    ]#
  var sz = 0
  var nbufs = 0
  var drop_gil = true
  for i in 0 ..< seqlen:
    item = PySequence_Fast_GET_ITEM(sequ, i)
    proc asgn(b: auto) =
      buffers[i] = init_Py_buffer(to_py_buffer(b), b.len, item)
    if item.ofExactPyBytesObject:
      # Fast path.
      let b = PyBytesObject(item)
      asgn b
    elif item.ofExactPyByteArrayObject:
      let b = PyByteArrayObject(item)
      asgn b
    else:
      template byteslikeExpect =
        return newTypeError newPyStr(
          fmt"sequence item {i}: expected a bytes-like object, {item.typeName:.80s} found"
        )
      when defined(npython_buffer):
        #TODO:buffer
        let exc: PyBaseErrorObject = PyObject_GetBuffer(item, buffers[i], PyBUF.SIMPLE)
        if not exc.isNil:
          byteslikeExpect
        #[ If the backing objects are mutable, then dropping the GIL
          opens up race conditions where another thread tries to modify
          the object which we hold a buffer on it. Such code has data
          races anyway, but this is a conservative approach that avoids
          changing the behaviour of that data race.
          ]#
        drop_gil = false
      else:
        byteslikeExpect

    nbufs = i + 1  # for error cleanup
    let itemlen = buffers[i].len
    template resTooLong =
      return newOverflowError newPyAscii"join() result is too long"
    template `+?=`(s: var int; i: int) =
      if i > int.high - s: resTooLong
      s += i
    sz +?= itemlen
    if i != 0:
      sz +?= seplen
    if seqlen != PySequence_Fast_GET_SIZE(sequ):
      return newRuntimeError newPyAscii"sequence changed size during iteration"

  # Allocate result space.
  var res = `newPy S`(sz)

  # Catenate everything.
  var p = 0
  when declared(copyMem):
    template memcpy(_, b; n: int) = copyMem(res.getCharPtr p, b[0].addr, n)
  else:
    template memcpy(_, b; n: int) =
      for i in 0..<n:#p ..< p+n:
        res.items[p+i] = b[i]
  template addbn(b; n: int) =
    memcpy(res[p], b, n)
    p += n
  template addb(bExpr: Py_buffer) =
    let b = bExpr
    addbn(b.buf, b.len)
  if sz < GIL_THRESHOLD:
    drop_gil = false   # Benefits are likely outweighed by the overheads
  
  #TODO:threads
  const hasPyThrd = defined(npython_threads)
  when hasPyThrd:
    var save: PyThreadState
    if drop_gil: save = PyEval_SaveThread()

  if seplen == 0:
    # fast path
    for i in 0..<nbufs:
      addb buffers[i]
  else:
    if nbufs > 0:
      addb(buffers[0])
      addbn(sepstr, seplen)
      for i in 1 ..< nbufs:
        addb(buffers[i])

  when hasPyThrd:
    if drop_gil: PyEval_RestoreThread(save)

  # RtArray's `=destroy` will call buffer's destroy
  #for b in buffers: PyBuffer_Release(b)
  #if use_non_static: PyMem_Free(buffers)
  return res


