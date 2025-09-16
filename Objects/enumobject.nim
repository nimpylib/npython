
import std/strformat
import ./[
  pyobject,
  tupleobject,
  exceptions,
  noneobject,
  stringobject,
  typeobject,
  dictobject,
]
import ./numobjects/intobject
import ./abstract/[
  iter, sequence,
]
import ../Python/[
  getargs, call,
]
import ../Python/getargs/va_and_kw
import ../Include/cpython/[
  pyatomic, critical_section,
]
import ../Include/internal/[
  pycore_global_strings,
]
import ./typeobject/apis/attrs

declarePyType Enumerate(mutable):
  index: int
  sit: PyObject
  result: PyTupleObject
  longindex: PyIntObject

template one(en: PyEnumerateObject): PyIntObject = pyIntOne

template newPyEnumerateImpl(typ, handleStart): untyped{.dirty.} =
  let res = typ.tp_alloc(typ, 0)
  retIfExc res
  let en = PyEnumerateObject res

  handleStart

  en.sit = PyObject_GetIter(iter)
  retIfExc en.sit
  en.result = PyTuple_Pack(pyNone, pyNone)
  en

template set_index(en: PyEnumerateObject; i: int) =
  en.index = i
  en.longindex = nil

template set_index(en: PyEnumerateObject; i: PyIntObject) =
  en.index = high int
  en.longindex = i

template set_index(en: PyEnumerateObject; i: PyObject) =
  var start = PyNumber_Index(i)
  retIfExc start
  assert start.ofPyIntObject

  let istart = PyIntObject start

  let exc = PyLong_AsSsize_t(istart, en.index)
  if not exc.isNil: # ovf
    en.set_index istart
  else:
    en.longindex = nil

proc newPyEnumerate*(iter: PyObject, start: PyObject, typ=pyEnumerateObjectType): PyObject =
  newPyEnumerateImpl typ:
    if not start.isNil:
      en.set_index start
    else:
      en.set_index 0

proc newPyEnumerate*(iter: PyObject, start: int = 0): PyObject =
  newPyEnumerateImpl pyEnumerateObjectType:
    en.set_index start

proc newPyEnumerate*(iter: PyObject, start: PyIntObject): PyObject =
  newPyEnumerateImpl pyEnumerateObjectType:
    en.set_index start

implEnumerateMagic New(typ: PyTypeObject, *actualArgs, **kw):
  retIfExc PyArg_ParseTupleAndKeywordsAs("enumerate.__new__", actualArgs, kw, [],
    iterable, start
  )
  newPyEnumerate(iterable, start, typ)

type enumobject = PyEnumerateObject

proc increment_longindex_lock_held(en: enumobject): PyIntObject{.inline.} =
  ## increment en_longindex with lock held, return the next index to be used
  var next_index = en.longindex
  if next_index.isNil:
    next_index = newPyInt int.high
  assert not next_index.isNil;
  let stepped_up = next_index + en.one
  en.longindex = stepped_up
  return next_index

proc enum_next_long(en: enumobject, next_item: PyObject): PyObject =
  result = en.result
  var next_index: PyObject

  #Py_BEGIN_CRITICAL_SECTION(en)
  criticalWrite(en):
    next_index = increment_longindex_lock_held(en)
  #Py_END_CRITICAL_SECTION()

  result = PyTuple_Pack(next_index, next_item)

proc next*(en: PyEnumerateObject): PyObject =
  ## enum_next
  result = en.result
  let it = en.sit

  let next_item = it.getMagic(iternext)(it)

  #if next_item.isNil: return nil
  # XXX: CPython's iter mode checks against nil and requires returns nil here
  if next_item.isStopIter: return next_item

  let en_index = Py_atomic_load_relaxed(FT en.index)
  if en_index == int.high:
    return enum_next_long(en, next_item)

  let next_index = newPyInt(en_index)
  Py_atomic_store_relaxed(FT en.index, en_index + 1)

  result = PyTuple_Pack(next_index, next_item)


implEnumerateMagic iternext: self.next()
implEnumerateMagic iter: self



# Reversed object ***********

declarePyType Reversed(mutable):
  index: int
  sequ: PyObject

type reversedobject = PyReversedObject

template noRev =
  return newTypeError newPyStr &"'{sequ.typeName:.200s}' object is not reversible"
proc newPyReversed*(sequ: PyObject; typ=pyReversedObjectType): PyObject =
  let reversed_meth = PyObject_LookupSpecial(sequ, pyDUId reversed)
  if reversed_meth.isPyNone: noRev
  if not reversed_meth.isNil:
    if reversed_meth.isThrownException:
      return reversed_meth
    return call reversed_meth

  # is nil. not found
  if not PySequence_Check(sequ):
    noRev
  var n: int
  retIfExc PySequence_Size(sequ, n)
  assert n != -1
  let roE = typ.tp_alloc(typ, 0)
  retIfExc roE
  let ro = reversedobject roE
  ro.index = n-1
  ro.sequ = sequ
  return ro

using ro: reversedobject
proc next*(ro): PyObject =
  ## reversed_next
  let index = Py_atomic_load_relaxed(FT ro.index)
  if index >= 0:
    let item = PySequence_GetItem(ro.sequ, index)
    if item.isThrownException:
      if not (
        item.ofPyIndexErrorObject or item.ofPyStopIterErrorObject
      ): return item
      else:
        discard item
    else:
      Py_atomic_store_relaxed(FT ro.index, index-1)
      return item
  Py_atomic_store_relaxed(FT ro.index, -1)
  newStopIterError()

proc getLen*(ro; res: var int): PyBaseErrorObject =
  template ret(i: int) =
    res = i
    return nil
  let index = Py_atomic_load_relaxed(FT ro.index)
  if index == -1:
    ret 0
  assert not ro.sequ.isNil
  var seqsize: int
  retIfExc PySequence_Size(ro.sequ, seqsize)
  let position = index + 1
  ret if seqsize < position: 0 else: position

implReversedMagic New(typ: PyTypeObject, x: PyObject):
  newPyReversed(x, typ)

implReversedMagic len:
  var res: int
  retIfExc self.getLen(res)
  result = newPyInt res

implReversedMagic iter: self
implReversedMagic iternext: self.next()

