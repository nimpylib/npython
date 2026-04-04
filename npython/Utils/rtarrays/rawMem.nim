

## As of Nim 2.3.1, std/rtarrays is unstable and only contains two routiues
##  and even cannot get length!

#[
import std/rtarrays
const useStd = compiles:
  var a: RtArray[int]
  static: assert a.getRawData[0] is int
  static: assert a.len is int
]#
import ./utils
const useStd = false
type
  RtArray*[T] = object
    L: int
    data: ptr UncheckedArray[T]

using self: RtArray


template whenNotStd(orUse): untyped =
  when not useStd: orUse
template stdOr(stdUse, orUse): untyped =
  when useStd: stdUse
  else: orUse

whenNotStd:
  import ../destroyPatch

proc getRORawData*[T](self: RtArray[T]): ptr UncheckedArray[T] =
  stdOr:
    cast[var RtArray[T]](self).getRawData
  do:
    self.data


proc `[]`*[T](self: RtArray[T]; i: int): T =
  chkIdx i, self.len
  self.getRORawData[i]

whenNotStd:
  proc getRawData*[T](self: var RtArray[T]): ptr UncheckedArray[T] =
    ## we only gant to return a writable view of `self`,
    ##   may not be ptr UncheckedArray in the future
    self.data

  template allocCArray[T](size: int): untyped =
    cast[ptr UncheckedArray[T]](alloc0 size)
  template allocCArray[T](len: int): untyped =
    ## inject cArrSize
    allocCArray[T](size = len * sizeof(T))

  proc initRtArray*[T](len: Natural): RtArray[T] =
    result.L = len
    result.data = allocCArray[T](len=len)

  proc len*(self): int = self.L

  defdestroy RtArray[auto]:
    if self.data.isNil:
      return
    when compiles(self.data[0].`=destroy`):
      for i in 0..<self.len:
        self.data[i].`=destroy`
    dealloc self.data

  when defined(nimHasTrace):
    proc `=trace`*[T](dest: var RtArray[T]; env: pointer) =
      if dest.len != 0:
        # trace the `T`'s which may be cyclic
        for i in 0 ..< dest.len: `=trace`(dest.data[i], env)

  proc `=wasMoved`*[T](self: var RtArray[T]) =
    self.L = 0
    self.data = nil

  # system.`=sink` and `=dup` is enough

  proc `=copy`*[T](dest: var RtArray[T], src: RtArray[T]) =
    dest.L = src.L
    let cArrSize = src.L * sizeof(T)
    dest.data = allocCArray[T](size=cArrSize)
    copyMem(dest.data[0].addr, src.data[0].addr, cArrSize)


proc `[]=`*[T](self: var RtArray[T]; i: int; val: T) =
  chkIdx i, self.len
  self.getRawData[i] = val


proc initRtArray*[T](oa: openArray[T]): RtArray[T] =
  result = initRtArray[T](oa.len)
  let p = result.getRawData()
  for i, v in oa:
    p[i] = v

iterator items[T](p: ptr UncheckedArray[T], L: int): T =
  for i in 0..<L: yield p[i]

iterator pairs[T](p: ptr UncheckedArray[T], L: int): (int, T) =
  for i in 0..<L: yield (i, p[i])

iterator items*[T](self: RtArray[T]): T =
  let p = self.getRORawData()
  for v in p.items self.len:
    yield v

iterator pairs*[T](self: RtArray[T]): (int, T) =
  let p = self.getRORawData()
  for i, v in p.pairs self.len:
    yield (i, v)

proc `@`*[T](self: RtArray[T]): seq[T] =
  let p = self.getRORawData()
  self.atImpl(p)

template getAcc(p; self) =
  let p = self.getRORawData()

proc `$`*(self): string =
  dollarImpl(self, getAcc)

template genCmp(op){.dirty.} =
  proc op*[T](self, o: RtArray[T]): bool =
    let L = self.len
    if not L.op o.len: return
    let
      p1 = self.getRORawData()
      p2 = o.getRORawData()
    when declared(cmpMem):
      cmpMem(p1, p2, L * sizeof(T)).op 0
    else:
      for i, v in p1.pairs L:
        if not v.op p2[i]:
          return
      return true

genCmp `==`
