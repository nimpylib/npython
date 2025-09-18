
import std/strformat
import ../../Objects/[
  pyobject,
  tupleobjectImpl,
  exceptions,
  noneobject,
  stringobject,
]
import ../../Objects/abstract/[
  iter, sequence,
]
import ../getargs/[kwargs, tovals,]

# zip object *********
declarePyType Zip():
  tuplesize: int
  ittuple: PyTupleObject  ## tuple of iterators
  result: PyTupleObject
  strict: bool

type zipobject = PyZipObject

template newPyZipImpl(tp_alloc_may_exc: static bool; args: PyTupleObject; tstrict: bool; typ=pyZipObjectType) =
  let
    tuplesize = args.len

  # create a result holder
  let res = PyTuple_Collect:
    for i in 0..<tuplesize:
      pyNone
  
  result = zipobject typ.tp_alloc(typ, 0)
  when tp_alloc_may_exc:
    retIfExc result
  let lz = zipobject result

  lz.ittuple = PyTuple_Collect:
    for item in args:
      let it = PyObject_GetIter(item)
      if it.isThrownException:
        return it
      it
  lz.tuplesize = tuplesize
  lz.result = res
  lz.strict = tstrict

proc newPyZip*(args: openArray[PyObject], strict: bool; typ: PyTypeObject): PyObject =
  newPyZipImpl(true, newPyTuple args, strict, typ)
proc newPyZip*(args: openArray[PyObject], strict=false): PyObject =
  newPyZipImpl(false,newPyTuple args, strict, pyZipObjectType)

proc newPyZip*(args: PyTupleObject, strict: bool; typ: PyTypeObject): PyObject =
  newPyZipImpl(true, args, strict, typ)
proc newPyZip*(args: PyTupleObject, strict=false): PyObject =
  newPyZipImpl(false, args, strict, pyZipObjectType)


implZipMagic New(tp: PyObject, *its, **kw):
  var strict = false
  retIfExc PyArg_UnpackKeywordsTo("zip", kw, strict)
  newPyZip(its, strict, PyTypeObject tp)

template errShorter(funcname: string; i){.dirty.} =
  #[ValueError: zip() argument 2 is shorter than argument 1
    ValueError: zip() argument 3 is shorter than arguments 1-2]#
  let plural = if i == 1: " " else: "s 1-"
  return newValueError newPyAscii funcname & fmt"() argument {i+1} is shorter than argument{plural}{i}"
template goto_check(funcname: string; tup; i; titem) =
  if not titem.isStopIter: return titem
  if i != 0:
    errShorter funcname, i
  for i in 1..<tup.len:
    let
      it = tup[i]
      item = it.callMagic(iternext)
    if item.isNil: continue # XXX: I don't understand why CPython does so
    # and how can iternext return non-NULL while `!PyErr_Occurred`
    if not item.isThrownException:
      errShorter funcname, i
    else:
      if not item.isStopIter:
        return item

template loopIter(tup; funcname: string; body){.dirty.} =
  for i, it in tup:
    let item = it.callMagic(iternext)
    if item.isThrownException:
      if self.strict:
        goto_check(funcname, tup, i, item)
      return item
    body

using self: zipobject
proc next*(self): PyObject =
  ## zip_next
  let
    tuplesize = self.tuplesize
    res = self.result
  if tuplesize == 0:
    return newStopIterError()

  loopIter(self.ittuple, "zip"):
    res[i] = item
  return res


implZipMagic iternext: self.next()
implZipMagic iter: self

template reg(f) =
  registerBltinObject astToStr(f), `py f ObjectType`
template register_iter_objects* =
  reg zip


