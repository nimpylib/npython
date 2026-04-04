
import std/macros
import std/strformat
from std/algorithm import reverse
import ../Utils/[sequtils, destroyPatch, addr0]
import ./byteobjects
import ./pyobject
import ./[boolobject, numobjects, stringobjectImpl, exceptions, noneobject,
  iterobject, hash, abstract,
  bltcommon,
]
import ./tupleobjectImpl
import ./stringobject/private/utils
import ./stringlib/join
import pkg/pystrutils
from ./listobject import genMutableSequenceMethods, newPyList, PyListObject, add
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

#TODO:buffer
# workaround:
type Py_buffer = object
  buf: CharsView
  len: int
  obj: PyObject
defdestroy Py_buffer: discard
#proc PyBuffer_Release(b: Py_buffer) = discard

proc init_Py_buffer(buf: CharsView, len: int, obj: PyObject, ): Py_buffer = Py_buffer(buf: buf, len: len, obj: obj)

proc to_py_buffer(b: PyBytesObject|PyByteArrayObject): CharsView = b.charsView

proc init_Py_buffer(buf: PyBytesObject|PyByteArrayObject): Py_buffer{.raises: [].} =
  init_Py_buffer(buf.to_py_buffer, buf.len, buf)

macro addVars(call; vargs: varargs[untyped]): untyped =
  result = call
  for arg in vargs:
    result.add arg

proc toval(o: PyObject, val: var Py_buffer): PyBaseErrorObject =
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
  proc split*(self: `Py B Object`; sep = PyObject pyNone, maxsplit = -1): PyObject{.clinicGenMethodRaises(B, [ValueError]).} =
    if sep.isPyNone: `pack B List` self.items.split(maxsplit)
    else: `pack B List` doCorS(seq[seq[char]], split, sep, maxsplit)


template gen_strip(strip, B){.dirty.} =
  proc strip*(self: `Py B Object`; chars = PyObject pyNone): PyObject{.clinicGenMethodRaises(B, [ValueError]).} =
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

template implCommons(B, mutRead){.dirty.} =
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

implCommons bytes, []
implCommons bytearray, [mutable: read]


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

# TODO: encoding, errors params
implBytesMagic New(tp: PyObject, x: PyObject):
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
