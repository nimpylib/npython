
import std/macros
import std/strformat
from std/algorithm import reverse
import ../Utils/[sequtils, addr0]
import ./byteobjects
import ./pyobject
import ./numobjects/intobject
import ./[boolobject, numobjects, stringobjectImpl, exceptions, noneobject,
  iterobject, hash, abstract,
  bltcommon,
  listobject,
  pybuffer, memoryobject,
]
import ./tupleobjectImpl
import ./stringobject/private/utils
import ./stringlib/join
import ./abstract/pybuffer
import pkg/pystrutils
import ../Python/getargs/[va_and_kw, dispatch]
import ../Utils/[sequtils2]

export byteobjects

proc `&`(s: string, se: seq[char]): string =
  result.setLen s.len + se.len
  result.add s
  when declared(copyMem):
    copyMem result[s.len].addr, se.addr0, se.len
  else:
    for i in se: result.add i
template `&`(se: seq[char], s: string): seq[char] = se & @s

macro addVars(call; vargs: varargs[untyped]): untyped =
  result = call
  for arg in vargs:
    result.add arg

template doCorS(Res; doSth; o; args: varargs[untyped]): untyped{.dirty.} =
  const hasRes = Res is_not void
  when hasRes:
    var `res doSth`{.genSym.}: Res
  block binDoSth:
    when hasRes:
      template doRes(x) = `res doSth` = x
    else:
      template doRes(x) = x
    doRes addVars(doSth(self.items,
      o.PyNumber_AsCharOr("bytes") do:
        if o.ofPyBytesObject:
          let ob = o.PyBytesObject
          doRes addVars(self.items.doSth(ob.items), args)
          break binDoSth
        elif o.ofPyByteArrayObject:
          let ob = o.PyByteArrayObject
          doRes addVars(self.items.doSth(ob.items), args)
          break binDoSth
        else:
          # TODO:buffer
          return bufferNotImpl()
        # return self.doSth s
    ), args)
  when hasRes:
    `res doSth`

template binDoCorS(doSth, o): untyped{.dirty.} = 
  type Res = typeof(self.items.doSth('\0'))
  doCorS(Res, doSth, o)

template genMapper(B, name; nName: untyped = name){.dirty.} =
  proc name*(self: `Py B Object`): `Py B Object`{.clinicGenMethod(B).} =
    `newPy B` self.items.nName()

template gen_removesuffix(B, removesuffix){.dirty.} =
  proc removesuffix*(self: `Py B Object`, suffix: Py_buffer): `Py B Object`{.clinicGenMethod(B).} =
    `newPy B` self.items.removesuffix(suffix.buf.toOpenArray(0, suffix.buf.high))
  # proc removesuffix*(self: `Py B Object`, suffix: `Py B Object`): `Py B Object`{.clinicGenMethod(B).} =
  #   `newPy B` self.items.removesuffix(suffix.items)

template doFind(self, target): untyped =
  ## helper to avoid too much `...it2, start, stop)` code snippet
  find(self, target, start, stop)
template doRFind(self, target): untyped =
  ## helper to avoid too much `...it2, start, stop)` code snippet
  rfind(self, target, start, stop)

template gen_split(split, B){.dirty.} =
  proc split*(self: `Py B Object`; sep = pyNoneObj, maxsplit = -1): PyObject{.clinicGenMethodRaises(B, [ValueError]).} =
    if sep.isPyNone: `pack B List` self.items.split(maxsplit)
    else: `pack B List` doCorS(seq[seq[char]], split, sep, maxsplit)


template gen_strip(strip, B){.dirty.} =
  proc strip*(self: `Py B Object`; chars = pyNoneObj): PyObject{.clinicGenMethodRaises(B, [ValueError]).} =
    if chars.isPyNone: `newPy B` self.items.strip()
    else: `newPy B` binDoCorS(strip, chars)


template gen_startswith(startswith, prefix, B){.dirty.} =
  proc startswith*(self: `Py B Object`, prefix: PyBytesObject|PyByteArrayObject, start = 0, `end` = self.len): bool =
    self.items.startswith(prefix.items, start, `end`)

  proc startswith*(self: `Py B Object`, prefix: PyTupleObject, start = 0, `end` = self.len): bool =
    template typeErr =
      raise newException(TypeError, fmt"tuple for {astToStr(startswith)} must only contain {astToStr(B)}, not {i.typeName:.100s}")
    for i in prefix:
      #TODO:buffer
      if not i.`ofPy B Object`: typeErr
      let si = `Py B Object`(i)
      if self.items.startswith(si.items, start, `end`): return true

  proc startswith*(self: `Py B Object`, prefix: PyObject, start = 0, `end` = self.len): bool =
    if prefix.`ofPy B Object`:
      self.startswith(`Py B Object`(prefix), start, `end`)
    elif prefix.ofPyTupleObject:
      self.startswith(PyTupleObject prefix, start, `end`)
    else:
      let n = prefix.typeName
      raise newException(TypeError,
        strformat.fmt"{astToStr(startswith)} first arg must be str or a tuple of {astToStr(B)}, not {n:.100s}")
  
  `impl B Method` startswith(prefix: PyObject, start = 0, `end` = int.high):
    retTypeError newPyBool self.startswith(prefix, start, self.cap_stop `end`)

template genFindIndex(index, find, doFind, mutRead, B){.dirty.} =
  `impl B Method` find, mutRead:
    implMethodGenTargetAndStartStop()
    newPyInt binDoCorS(doFind, target)
  `impl B Method` index, mutRead:
    implMethodGenTargetAndStartStop()
    let res = binDoCorS(doFind, target)
    if res >= 0:
      return newPyInt(res)
    newValueError(newPyAscii"subsection not found")

template gen_adjust(adjust, B){.dirty.} =
  proc adjust*(self: `Py B Object`, width: int, fillchar = init_Py_buffer `newPy B` [' ']
  ): `Py B Object`{.clinicGenMethodRaises(B, [TypeError]).} =
    `newPy B` self.items.adjust(width, fillchar.buf.toOpenArray(0, fillchar.buf.high))


template genPredict(name, B){.dirty.} =
  proc name*(self: `Py B Object`): bool{.clinicGenMethod(B).} = self.items.name()

proc expandtabs[C](a: openArray[C], tabsize=8): seq[C] =
  expandtabsImpl(a, tabsize, a.len, items, newSeqOfCap[C])

template toval(obj: bool, val: var PyObject): PyBaseErrorObject =
  val = newPyBool obj
  nil

template implCommons(B, readonly, mutRead){.dirty.} =
  methodMacroTmpl(B)
  type `T B` = `Py B Object`
  `impl B Magic` eq:
    if not other.`ofPy B Object`:
      return pyFalseObj
    return newPyBool self == `T B`(other)
  `impl B Magic` len, mutRead: newPyInt self.len
  `impl B Magic` repr, mutRead: newPyAscii(repr self)
  genGetitem astToStr(B), `impl B Magic`, `newPy B`, mutRead, getInt
  `impl B Magic` iter, mutRead:
    genPyNimIteratorIter self.ints
  `impl B Magic` contains, mutRead:
    newPyBool binDoCorS(contains, other)
    #fmt"argument should be integer or bytes-like object, not '{other.pyType.name:.200s}'")

  `impl B Magic` add, mutRead:
    template retRes(o): untyped = `newPy B`(self.items & o.items)
    if other.ofPyBytesObject:
      retRes PyBytesObject(other)
    elif other.ofPyByteArrayObject:
      retRes PyByteArrayObject(other)
    else:
      # TODO:buffer
      newTypeError newPyStr(
        fmt"can't concat {self.pyType.name:.100s} to {other.pyType.name:.100s}"
      )

  genFindIndex index, find, doFind, mutRead, B
  genFindIndex rindex, rfind, doRFind, mutRead, B

  `impl B Method` count:
    implMethodGenTargetAndStartStop()
    var count: int
    template cntAll(it, o) =
      for _ in findAll(it, o, start, stop): count.inc
    binDoCorS(cntAll, target)
    newPyInt(count)

  #TODO:bytes: always returns tuple of 3 empty bytes
  template `pack B List`(itor): PyListObject =
    let res = newPyList()
    for it in itor:
      res.add `newPy B`(it)
    res

  
  gen_split split, B
  gen_split rsplit, B

  gen_strip strip, B
  gen_strip lstrip, B
  gen_strip rstrip, B

  gen_startswith startswith, prefix, B
  gen_startswith endswith, suffix, B

  gen_adjust center, B
  gen_adjust ljust, B
  gen_adjust rjust, B

  proc zfill*(self: `Py B Object`, width: int): `Py B Object`{.clinicGenMethod(B).} =
    `newPy B` self.items.zfill(width)

  proc expandtabs*(self: `Py B Object`, tabsize = 8): `Py B Object`{.clinicGenMethod(B).} =
    `newPy B` self.items.expandTabs(tabsize)

  genPredict isalnum, B
  genPredict isalpha, B
  genPredict isascii, B
  genPredict isdigit, B

  genPredict islower, B


  genPredict isspace, B
  genPredict istitle, B
  genPredict isupper, B

  genMapper B, capitalize

  genMapper B, lower, toLower
  genMapper B, upper, toUpper
  #genMapper B,  swapcase
  genMapper B, title, toTitle

  gen_removesuffix B, removesuffix
  gen_removesuffix B, removeprefix

  #TODO:bytes: always returns tuple of 3 empty bytes
  template `pack B Tuple`(tup): PyTupleObject =
    PyTuple_Collect:
      for it in tup:
        `newPy B`(it)
  `impl B Method` partition(sep):
    # try:
    #   let ssssss{.exportc.} = self.items.partition(sep.PyBytesObject.items)
    #   retValueErrorAscii `pack B Tuple`(ssssss)
    # except ValueError: doAssert false
    retValueErrorAscii `pack B Tuple`(binDoCorS(partition, sep))
  `impl B Method` rpartition(sep):
    retValueErrorAscii `pack B Tuple`(binDoCorS(rpartition, sep))
  `impl B Method` splitlines(keepends = false): `pack B List` self.items.splitLines(keepends)

  `impl B Method` replace(old: PyObject, `new`: PyObject, count = -1):
    #TODO:buffer
    if old.ofPyBytesObject and `new`.ofPyBytesObject:
      `newPy B`(self.items.replace(PyBytesObject(old).items, PyBytesObject(`new`).items, count))
    elif old.ofPyByteArrayObject and `new`.ofPyByteArrayObject:
      `newPy B`(self.items.replace(PyByteArrayObject(old).items, PyByteArrayObject(`new`).items, count))
    else:
      bufferNotImpl()
  `impl B Magic` buffer, mutRead:
    let iobj = other.castTypeOrRetTE PyIntObject
    let flags = iobj.toIntOrRetOF
    var view: Py_buffer
    retIfExc PyBuffer_FillInfo(view, self,
      self.charsView, self.len,
      readonly, PyBufferFlags flags)
    newPyMemoryView view

implCommons bytes,     true, []
implCommons bytearray, false,[mutable: read]


implBytesMagic hash: newPyInt self.hash

implBytesMagic bytes: self
implByteArrayMagic bytes, [mutable: read]: newPyBytes self.items

genMutableSequenceMethods PyNumber_AsCharOrRet, newPyInt, ByteArray, char:
  # before append
  when compileOption"boundChecks":
    if self.len == high int:
      return newOverflowError newPyAscii"cannot add more objects to bytearray"

template genJoin(B; mut: bool){.dirty.} =
  proc join*(b: `Py B Object`, iterable: PyObject): PyObject{.pyCFuncPragma.} =
    bytes_join B, b, iterable, mutable=mut
  `impl B Method` join(iterable): self.join iterable

genJoin bytes, false
genJoin bytearray, true

template impl(x, fromSize, fromObject) =
  if x.ofPyStrObject:
    return newTypeError newPyAscii"string argument without an encoding"
  # Is it an integer?
  let fun = x.getMagic(index)
  if not fun.isNil:
    var size: int
    result = PyNumber_AsSsize_t(x, size)
    if size == -1 and result.isThrownException:
      if not result.isExceptionOf ExceptionToken.Type:
        return  # OverflowError
      fromObject x
    else:
      if size < 0:
        return newValueError newPyAscii"negative count"
      fromSize size
  else:
    fromObject x


template objAsBuffer(view, x) {.dirty.} =
  var view: Py_buffer
  retIfExc PyObject_GetBuffer(x, view, PyBUF.FULL_RO)
  defer: retIfExc PyBuffer_Release view

proc newPyBytesFrom_Buffer*(x: PyObject): PyObject =
  objAsBuffer view, x
  var res = newPyBytes(view.len)
  retIfExc PyBuffer_ToContiguous(res.charsView, view, view.len, PyBufferOrder.C)
  return res

proc initFromBuffer(self: PyByteArrayObject, x: PyObject): PyBaseErrorObject =
  objAsBuffer view, x
  retIfExc PyBuffer_ToContiguous(self.charsView, view, view.len, PyBufferOrder.C)

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
  mixin fromList, fromTuple, fromIterator, fromBuffer
  if x.ofPyBuffer(): fromBuffer x
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

template genFrom(ls, tup, itor, buf){.dirty.} =
  template fromList(x) = ls
  template fromTuple(x) = tup
  template fromIterator(x) = itor
  template fromBuffer(x) = buf

proc PyBytes_FromObject*(x: PyObject): PyObject =
  if x.pyType == pyBytesObjectType: return x
  genFrom: return PyBytes_FromList PyListObject x
  do:      return PyBytes_FromTuple PyTupleObject x
  do:      return PyBytes_FromIterator(it)
  do:      return newPyBytes_FromBuffer(x)
  fillFromObject x

proc initFromObject*(self: PyByteArrayObject, x: PyObject): PyBaseErrorObject =
  template retOnE(exp: PyBaseErrorObject) =
    let e = exp
    if not e.isNil: return e
    else: return
  genFrom: retOnE self.initFromList PyListObject x
  do:      retOnE self.initFromTuple PyTupleObject x
  do:      retOnE self.initFromIterator(it)
  do:      retOnE self.initFromBuffer(x)
  fillFromObject x

proc PyByteArray_FromObject*(x: PyObject): PyObject =
  let self = newPyByteArray()
  result = self.initFromObject x
  if result.isNil: return self

# TODO: encoding, errors params
implBytesMagic New(_: PyObject, x: PyObject):
  var bytes: PyObject
  let fun = x.getMagic(bytes)
  if not fun.isNil:
    result = fun(x)
    if not result.ofPyBytesObject:
      return newTypeError newPyString(
        &"__bytes__ returned non-bytes (type {result.pyType.name:.200s})")
    return

  template fromSize(size) = bytes = newPyBytes size
  template fromObject(o) = bytes = PyBytes_FromObject o
  impl x, fromSize, fromObject
  return bytes


# TODO: encoding, errors params
implByteArrayMagic init:
  if args.len == 0:
    return pyNone
  checkArgNum 1  # TODO
  let x = args[0]
  if self.items.len != 0:
    self.items.setLen(0)

  template fromSize(size) = self.setLen size
  template fromObject(o) =
    let e = self.initFromObject o
    if not e.isNil: return e
  impl x, fromSize, fromObject
  pyNone
