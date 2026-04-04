
import std/strformat
import ../../Objects/[
  pyobject,
  tupleobjectImpl,
  exceptions,
  boolobjectImpl,
  noneobject,
  stringobject,
]
import ../call
import ../../Objects/abstract/[
  iter, sequence,
]
import ../getargs/[kwargs, tovals,]
import ./utils

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

  res.withSetitem acc:
    loopIter(self.ittuple, "zip"):
      acc[i] = item
  return res


implZipMagic iternext: self.next()
implZipMagic iter: self


# map object **********
declarePyType Map():
  iters: PyTupleObject
  fun: PyObject
  strict: bool


type mapobject = PyMapObject

template newPyMapImpl(tp_alloc_may_exc: static bool; args: PyTupleObject, tfun: PyObject; tstrict: bool; typ=pyMapObjectType) =
  #  Get iterator.
  let iters = PyTuple_Collect:
    for item in args:
      let it = PyObject_GetIter(item)
      retIfExc it
      it
  # create mapobject structure
  let res = typ.tp_alloc(typ, 0)
  when tp_alloc_may_exc:
    retIfExc res
  let lz = mapobject res
  lz.iters = iters
  lz.fun = tfun
  lz.strict = tstrict
  result = lz
  
proc newPyMap*(args: openArray[PyObject], fun: PyObject, strict: bool; typ: PyTypeObject): PyObject =
  newPyMapImpl(true, newPyTuple args, fun, strict, typ)
proc newPyMap*(args: openArray[PyObject], fun: PyObject, strict=false): PyObject =
  newPyMapImpl(false,newPyTuple args, fun, strict, pyMapObjectType)

proc newPyMap*(args: PyTupleObject, fun: PyObject, strict: bool; typ: PyTypeObject): PyObject =
  newPyMapImpl(true, args, fun, strict, typ)
proc newPyMap*(args: PyTupleObject, fun: PyObject, strict=false): PyObject =
  newPyMapImpl(false, args, fun, strict, pyMapObjectType)

implMapMagic New(tp: PyObject, fun, *iters, **kw):
  var strict = false
  retIfExc PyArg_UnpackKeywordsTo("map", kw, strict)
  newPyMap(iters, fun, strict, PyTypeObject tp)

using self: mapobject
proc next*(self): PyObject =
  var stack = newSeqOfCap[PyObject](self.iters.len)
  loopIter self.iters, "map":
    stack.add item
  fastCall(self.fun, stack)

implMapMagic iternext: self.next()
implMapMagic iter: self

# filter object **********
declarePyType Filter():
  fun: PyObject
  it: PyObject

type filterobject = PyFilterObject

template newPyFilterImpl(tp_alloc_may_exc: static bool; tfunc: PyObject, tseq: PyObject; typ=pyFilterObjectType) =
  #  Get iterator.
  let it = PyObject_GetIter(tseq)
  retIfExc it
  # create filterobject structure
  let res = typ.tp_alloc(typ, 0)
  when tp_alloc_may_exc:
    retIfExc res
  let lz = filterobject res
  lz.it = it
  lz.fun = tfunc
  result = lz
  
proc newPyFilter*(fun, sequ: PyObject, typ: PyTypeObject): PyObject =
  newPyFilterImpl(true, fun, sequ, typ)
proc newPyFilter*(fun, sequ: PyObject): PyObject =
  newPyFilterImpl(false,fun, sequ, pyFilterObjectType)

implFilterMagic New(tp: PyObject, fun, sequ):
  newPyFilter(fun, sequ, PyTypeObject tp)

using self: filterobject
proc next*(self): PyObject =
  let checktrue = self.fun.isPyNone or self.fun.Py_IS pyBoolObjectType

  let it = self.it
  let iternext = it.getMagic(iternext)
  var item: PyObject
  var ok: bool
  while true:
    item = iternext(it)
    retIfExc item
    retIfExc(
      if checktrue:
        PyObject_IsTrue(item, ok)
      else:
        let good = self.fun.call(item)
        retIfExc good
        PyObject_IsTrue(good, ok)
    )
    if ok:
      return item

implFilterMagic iternext: self.next()
implFilterMagic iter: self

template register_iter_objects* =
  regobj zip
  regobj map
  regobj filter

