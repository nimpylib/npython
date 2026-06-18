## bytesobject and bytesarrayobject
import std/strformat
import pkg/pyrepr
import ./hash
import ./pyobject
import ./[listobject, tupleobjectImpl, stringobject, exceptions, noneobject]
import ./numobjects/intobject/[decl, ops_imp_warn]
import ../Utils/[addr0, nexportc]
import ./charsview/decl as charsview_decl
export charsview_decl
#XXX: Nim's string ops has bugs for NUL('\0') char, e.g. len('1\02') gives 2
declarePyType Bytes(tpToken):
  items: seq[char]
  setHash{.private.}: bool
  privateHash{.private.}: Hash

declarePyType ByteArray(reprLock, mutable):
  items: seq[char]

proc hash*(self: PyBytesObject): Hash =
  if self.setHash: return self.privateHash
  self.setHash = true
  result = Py_HashBuffer(self.items)
  self.privateHash = result

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

proc getData*(self: var PyBytesWriter): ptr char =
  ## PyBytesWriter_GetData
  self.s.addr0

proc finish*(self: sink PyBytesWriter): PyObject

proc `$`(self: seq[char]): string =
  result.setLen self.len
  when declared(copyMem):
    if self.len > 0:
      copyMem result[0].addr, self[0].addr, self.len
  else:
    for i, c in self: result[i] = c

type PyByteLike = PyBytesObject or PyByteArrayObject

proc `==`*(a, b: PyBytesObject): bool {. inline .} = a.hash == b.hash and a.items == b.items
proc `==`*(a, b: PyByteArrayObject): bool {. inline .} = a.items == b.items
proc len*(s: PyByteLike): int {. inline, cdecl .} = s.items.len
proc `$`*(s: PyByteLike): string = $s.items
proc asCString*(self: PyBytesObject): cstring{.npyexportc: "PyBytes_AsString".} = cstring $self.items
iterator items*(s: PyByteLike): char =
  for i in s.items: yield i
iterator ints*(s: PyByteLike): PyIntObject =
  for i in s: yield newPyInt i
proc contains*(s: PyByteLike, c: char): bool = c in s.items
proc `[]`*(s: PyByteLike, i: int): char = s.items[i]
proc getInt*(s: PyByteLike, i: int): PyIntObject = newPyInt s[i]

when not defined(js):
  proc getCharPtr*(s: PyByteLike; i: int): ptr char = addr s.items[i]  ## unstable.
  ##  not available on JS

type SingleChar = uint8|char|byte ## \
  ## unstable. exported just for clarity for reading.
when defined(doc):
  export SingleChar
template impl(B, InitT, newTOfLen, newTOfLenUninit){.dirty.} =
  proc asString*(s: `Py B Object`): string = $s.items
  when defined(js): 
    proc charsView*(s: `Py B Object`): var CharsView = s.items
  else:
    proc charsView*(s: `Py B Object`): CharsView = cast[cstring](s.items.addr0)
  method `$`*(s: `Py B Object`): string = s.asString
  proc `newPy B`*(s: sink InitT): `Py B Object` =
    result = `newPy B Simple`()
    result.items = s
  proc `newPy B FromOpenArray`[T: SingleChar](s: openArray[T]): `Py B Object` =
    var items = newTOfLenUninit s.len
    for i, b in s: items[i] = char(b)
    result = `newPy B` items
  proc `newPy B`*[T: SingleChar](s: openArray[T]): `Py B Object` =
    `newPy B FromOpenArray` s
  proc `newPy B`*(size: int): `Py B Object` =
    `newPy B` newTOfLen size
  proc `newPy B`*(c: char): `Py B Object` =
    result = `newPy B` 1
    result.items[0] = c

  proc `newPy B NotNil`*(s: cstring): `Py B Object` =
    ## .. warnings: return `None` if `s` is nil
    `newPy B`(
      when not defined(js):
        s.toOpenArray(0, s.high)
      else:
        $s
    )
  proc `newPy B`*(s: cstring): PyObject =
    if s.isNil: return pyNone
    `newPy B NotNil` s

  let `empty B` = `newPy B` newSeq[char]()
  proc `newPy B`*(): `Py B Object` = `empty B`

  proc `&`*(s1, s2: `Py B Object`): `Py B Object` =
    `newPy B`(s1.items & s2.items)

when declared(newSeqUninit):
  template newCharsUninit(size: int): seq[char] = newSeqUninit[char](size)
else:
  template newCharsUninit(size: int): seq[char] = newSeq[char](size)

impl Bytes, seq[char], newSeq[char], newCharsUninit
impl ByteArray, seq[char], newSeq[char], newCharsUninit


proc finish*(self: sink PyBytesWriter): PyObject =
  if self.use_bytearray: newPyByteArray move self.s
  else: newPyBytes move self.s

proc finish*(self: sink PyBytesWriter, res: PyObject) =
  if self.use_bytearray: PyByteArrayObject(res).items = move self.s
  else: PyBytesObject(res).items = move self.s

proc repr*(b: PyBytesObject): string =
  pyreprb $b.items

proc repr*(b: PyByteArrayObject): string =
  "bytearray(" &
    pyreprb $b.items &
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

