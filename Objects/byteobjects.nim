## bytesobject and bytesarrayobject
import std/strformat
import std/hashes
import ./pyobject
from ./abstract/iter import PyObject_GetIter
import ./[listobject, tupleobjectImpl, stringobject, exceptions, iterobject]
import ./numobjects/intobject/[decl, ops_imp_warn]
#XXX: Nim's string ops has bugs for NUL('\0') char, e.g. len('1\02') gives 2
declarePyType Bytes(tpToken):
  items: seq[char]
  setHash: bool
  privateHash: Hash

declarePyType ByteArray(reprLock, mutable):
  items: seq[char]

proc hash*(self: PyBytesObject): Hash = self.hashCollection

type PyBytesWriter* = object
  #overallocate*: bool
  use_bytearray*: bool
  s: seq[char]

proc allocated*(self: PyBytesWriter): int{.error: "this writer is dynamically allocated".}
proc initPyBytesWriter*(): PyBytesWriter = discard

proc len*(self: PyBytesWriter): int{.inline.} = self.s.len
proc add*(self: var PyBytesWriter, c: char){.inline.} = self.s.add c
proc reset*(self: var PyBytesWriter, cap: int=0) =
  ## like `_PyBytesWriter_Alloc`
  self.s = newSeqOfCap[char] cap
proc initPyBytesWriter*(cap: int): PyBytesWriter =
  result = initPyBytesWriter()
  result.reset cap
proc finish*(self: sink PyBytesWriter): PyObject

proc `$`(self: seq[char]): string =
  result.setLen self.len
  when declared(copyMem):
    if self.len > 0:
      copyMem result[0].addr, self[0].addr, self.len
  else:
    for i, c in self: result[i] = c

type PyByteLike = PyBytesObject or PyByteArrayObject

proc len*(s: PyByteLike): int {. inline, cdecl .} = s.items.len
proc `$`*(s: PyByteLike): string = $s.items
iterator items*(s: PyByteLike): char =
  for i in s.items: yield i
iterator ints*(s: PyByteLike): PyIntObject =
  for i in s: yield newPyInt i
proc contains*(s: PyByteLike, c: char): bool = c in s.items
proc `[]`*(s: PyByteLike, i: int): char = s.items[i]
proc getInt*(s: PyByteLike, i: int): PyIntObject = newPyInt s[i]

template impl(B, InitT, newTOfCap){.dirty.} =

  proc asString*(s: `Py B Object`): string = $s.items
  method `$`*(s: `Py B Object`): string = s.asString
  proc `newPy B`*(s: InitT = default InitT): `Py B Object` =
    result = `newPy B Simple`()
    result.items = s
  proc `newPy B`*(size: int): `Py B Object` =
    `newPy B` newTOfCap size
  proc `&`*(s1, s2: `Py B Object`): `Py B Object` =
    `newPy B`(s1.items & s2.items)

impl Bytes, seq[char], newSeq[char]
impl ByteArray, seq[char], newSeq[char]


proc finish*(self: sink PyBytesWriter): PyObject =
  if self.use_bytearray: newPyByteArray move self.s
  else: newPyBytes move self.s

proc finish*(self: sink PyBytesWriter, res: PyObject) =
  if self.use_bytearray: PyByteArrayObject(res).items = move self.s
  else: PyBytesObject(res).items = move self.s

proc newPyBytes*(s: openArray[char]): PyBytesObject = newPyBytes @s

proc repr*(b: PyBytesObject): string =
  'b' & '\'' & $b.items & '\'' # TODO

proc repr*(b: PyByteArrayObject): string =
  "bytearray(" &
    'b' & '\'' & $b.items & '\'' #[TODO]# &
  ')'
proc `[]=`*(s: PyByteArrayObject, i: int, c: char) = s.items[i] = c
proc add*(s: PyByteArrayObject, c: char) = s.items.add c

proc add*(self: PyByteArrayObject, b: PyByteLike) = self.items.add b.items
proc setLen*(self: PyByteArrayObject, n: int) = self.items.setLen n

template checkCharRangeOrRetVE*(value: int; errSubject="byte") =
  if value < 0 or value > 256:
    return newValueError newPyAscii(errSubject & " must be in range(0, 256)")

proc bufferNotImpl*(): PyNotImplementedErrorObject =
  ## TODO:buffer: delete this once buffer api is implemented
  newNotImplementedError newPyAscii"not impl for buffer api"

template PyNumber_AsCharOr*(vv: PyObject, errSubject="byte"; orDoIt): char =
  bind PyNumberAsClampedSsize_t, checkCharRangeOrRetVE
  var value: int
  block:
    let it{.inject.} = PyNumber_AsClampedSsize_t(vv, value)
    if not it.isNil:
      orDoIt
  checkCharRangeOrRetVE(value, errSubject)
  cast[char](value)

template PyNumber_AsCharOrRet*(vv: PyObject, errSubject="byte"): char =
  PyNumber_AsCharOr(vv, errSubject):
    return it

template fillFromIterable(writer: PyBytesWriter; x; forInLoop; errSubject: string) =
  forInLoop i, x:
    writer.add i.PyNumber_AsCharOrRet(errSubject)

template genFromIter(S; T; forInLoop; getLenHint: untyped=len){.dirty.} =
  proc `PyBytes_From S`(x: T): PyObject =
    var writer = initPyBytesWriter x.getLenHint
    writer.fillFromIterable(x, forInLoop, "bytes")
    writer.finish
  proc `initFrom S`(self: PyByteArrayObject, x: T): PyBaseErrorObject =
    var writer = initPyBytesWriter x.getLenHint
    writer.use_bytearray = true
    writer.fillFromIterable(x, forInLoop, "byte")
    writer.finish self

template sysForIn(x, it, body){.dirty.} =
  for x in it: body 
genFromIter List, PyListObject, sysForIn
genFromIter Tuple, PyTupleObject, sysForIn
template getLenHint(x): int = 64  # TODO
genFromIter Iterator, PyObject, pyForIn, getLenHint

template fillFromObject(x: PyObject){.dirty.} =
  mixin fromList, fromTuple, fromIterator
  # TODO
  #[    /* Use the modern buffer interface */
    if (PyObject_CheckBuffer(x))
        return _PyBytes_FromBuffer(x);]#
  if x.pyType == pyListObjectType: fromList x
  if x.pyType == pyTupleObjectType: fromTuple x
  if not x.ofPyStrObject:
    let it = PyObject_GetIter(x)
    if not it.isThrownException:
      fromIterator it
    if not it.isExceptionOf Type:
      return PyBaseErrorObject it
  return newTypeError newPyStr(
    fmt"cannot convert '{x.pyType.name:.200s}' object to bytes"
  )

template genFrom(ls, tup, itor){.dirty.} =
  template fromList(x) = ls
  template fromTuple(x) = tup
  template fromIterator(it) = itor

proc PyBytes_FromObject*(x: PyObject): PyObject =
  if x.pyType == pyBytesObjectType: return x
  genFrom: return PyBytes_FromList PyListObject x
  do:      return PyBytes_FromTuple PyTupleObject x
  do:      return PyBytes_FromIterator(it)
  fillFromObject x

proc initFromObject*(self: PyByteArrayObject, x: PyObject): PyBaseErrorObject =
  template retOnE(exp: PyBaseErrorObject) =
    let e = exp
    if not e.isNil: return e
    else: return
  genFrom: retOnE self.initFromList PyListObject x
  do:      retOnE self.initFromTuple PyTupleObject x
  do:      retOnE self.initFromIterator(it)
  fillFromObject x

proc PyByteArray_FromObject*(x: PyObject): PyObject =
  let self = newPyByteArray()
  result = self.initFromObject x
  if result.isNil: return self
