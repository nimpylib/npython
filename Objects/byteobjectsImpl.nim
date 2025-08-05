
import std/strformat
import ../Utils/sequtils
import ./byteobjects
import ./pyobject
import ./[boolobject, numobjects, stringobjectImpl, exceptions, noneobject,
  iterobject, hash, abstract,
]
import ./tupleobjectImpl
from ./listobject import genMutableSequenceMethods

export byteobjects

proc `&`(s: string, se: seq[char]): string =
  result.setLen s.len + se.len
  result.add s
  when defined(copyMem):
    copyMem result[s.len].addr, se[0].addr, se.len
  else:
    for i in se: result.add i
template `&`(se: seq[char], s: string): seq[char] = se & @s

template binDoCorS(doSth, o): untyped{.dirty.} =
  block binDoSth:
    type Res = typeof(self.items.doSth('\0'))
    const hasRes = Res is_not void
    when hasRes:
      var res: Res
      template doRes(x) = res = x
    else:
      template doRes(x) = x
    doRes doSth(self.items,
      o.PyNumber_AsCharOr("bytes") do:
        if o.ofPyBytesObject:
          let ob = o.PyBytesObject
          doRes self.items.doSth(ob.items)
          break binDoSth
        elif o.ofPyByteArrayObject:
          let ob = o.PyByteArrayObject
          doRes self.items.doSth(ob.items)
          break binDoSth
        else:
          # TODO:buffer
          return bufferNotImpl()
        # return self.doSth s
    )
    when hasRes:
      res

template doFind(self, target): untyped =
  ## helper to avoid too much `...it2, start, stop)` code snippet
  find(self, target, start, stop)

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

  `impl B Method` find, mutRead:
    implMethodGenTargetAndStartStop()
    newPyInt binDoCorS(doFind, target)

  `impl B Method` index, mutRead:
    implMethodGenTargetAndStartStop()
    let res = binDoCorS(doFind, target)
    if res >= 0:
      return newPyInt(res)
    newValueError(newPyAscii"subsection not found")

  `impl B Method` count:
    implMethodGenTargetAndStartStop()
    var count: int
    template cntAll(it, o) =
      for _ in findAll(it, o, start, stop): count.inc
    binDoCorS(cntAll, target)
    newPyInt(count)


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
