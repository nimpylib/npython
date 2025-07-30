## bytesobject and bytesarrayobject
import std/strformat
import ./pyobject
import ./abstract
import ./[listobject, tupleobject, stringobject, exceptions, iterobject]

declarePyType Bytes(tpToken):
  items: string

declarePyType ByteArray(reprLock, mutable):
  items: seq[char]

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
proc finish*(self: PyBytesWriter): PyObject

template ofPyByteArrayObject*(obj: PyObject): bool =
  bind pyByteArrayObjectType
  obj.pyType == pyByteArrayObjectType

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
proc `[]`*(s: PyByteLike, i: int): char = s.items[i]

template impl(B, InitT, newTOfCap){.dirty.} =

  method `$`*(s: `Py B Object`): string = $s.items
  proc `newPy B`*(s: InitT = default InitT): `Py B Object` =
    result = `newPy B Simple`()
    result.items = s
  proc `newPy B`*(size: int): `Py B Object` =
    `newPy B` newTOfCap size
  proc `&`*(s1, s2: `Py B Object`): `Py B Object` =
    `newPy B`(s1.items & s2.items)

impl Bytes, string, newString
impl ByteArray, seq[char], newSeq[char]


proc finish*(self: PyBytesWriter): PyObject =
  if self.use_bytearray: newPyByteArray self.s
  else: newPyBytes $self.s

proc repr*(b: PyBytesObject): string =
  'b' & '\'' & b.items & '\'' # TODO

proc repr*(b: PyByteArrayObject): string =
  "bytearray(" &
    'b' & '\'' & $b.items & '\'' #[TODO]# &
  ')'
proc `[]=`*(s: PyByteLike, i: int, c: char) = s.items[i] = c

proc add*(self: PyByteArrayObject, b: PyByteLike) = self.items.add b.items

template genFromIter(S; T; forInLoop; getLenHint: untyped=len){.dirty.} =
  proc `PyBytes_From S`*(x: T): PyObject =
    let size = x.getLenHint
    var writer = initPyBytesWriter size
    var value: int
    forInLoop i, x:
      let ret = PyNumber_AsClampedSsize_t(i, value)
      if not ret.isNil:
        return ret
      if value < 0 or value > 256:
        return newValueError newPyAscii"bytes must be in range(0, 256)"
      writer.add cast[char](value)
    writer.finish

template sysForIn(x, it, body){.dirty.} =
  for x in it: body 
genFromIter List, PyListObject, sysForIn
genFromIter Tuple, PyTupleObject, sysForIn
template getLenHint(x): int = 64  # TODO
genFromIter Iterator, PyObject, pyForIn, getLenHint


proc PyBytes_FromObject*(x: PyObject): PyObject =
  if x.pyType == pyBytesObjectType: return x
  # TODO
  #[    /* Use the modern buffer interface */
    if (PyObject_CheckBuffer(x))
        return _PyBytes_FromBuffer(x);]#
  if x.pyType == pyListObjectType: return PyBytes_FromList PyListObject x
  if x.pyType == pyTupleObjectType: return PyBytes_FromTuple PyTupleObject x
  if not x.ofPyStrObject:
    let it = PyObject_GetIter(x)
    if not it.isNil:
      return PyBytes_FromIterator(it)
    if not it.isExceptionOf Type:
      return it
  return newTypeError newPyStr(
    fmt"cannot convert '{x.pyType.name:.200s}' object to bytes"
  )


