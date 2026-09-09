
import ./utils
import pkg/jscompat/utils/[jsarraybuffer, jsdataview]
export defLittleEndian

type
  NPointer* = ref object of RootObj
  NPointerSingle = ref object of NPointer
    d: DataView[ArrayBuffer]  ## XXX: impl is unstable, later maybe `ref object`
  NPointerShared = ref object of NPointer
    d: DataView[SharedArrayBuffer]

using n: int
proc alloc*(n): NPointer = NPointerSingle(d: newDataView newArrayBuffer n)
proc alloc0*(n): NPointer = alloc(n)

proc allocShared*(n): NPointer = NPointerShared(d: newDataView newSharedArrayBuffer n)
proc allocShared0*(n): NPointer = allocShared(n)

using p: NPointer
proc dealloc*(p) = discard
proc deallocShared*(p) = discard

proc repr*(d: NPointer): string = "[object DataView]"
#proc repr*(d: NPointer): string = "[object]"

template genMeth(NPointer, g, s, T, g1, s1) {.dirty.} =
  method g*(d: NPointer, i: int, isLittleEndian=defLittleEndian): T = d.d.g1(i, isLittleEndian)
  method s*(d: NPointer, i: int, v: T, isLittleEndian=defLittleEndian) = d.d.s1(i, v, isLittleEndian)

template genGS(g, s, T, _, g1: untyped = g; s1: untyped = s){.dirty.} =
  method g*(d: NPointer, i: int, isLittleEndian=defLittleEndian): T {.base, raises: [].} = unreachable
  method s*(d: NPointer, i: int, v: T, isLittleEndian=defLittleEndian) {.base, raises: [].} = unreachable
  genMeth NPointerSingle, g, s, T, g1, s1
  genMeth NPointerShared, g, s, T, g1, s1

template genBigI(int64) {.dirty.} =
  genGS `get int64`, `set int64`, int64, 64, `getBig int64`, `setBig int64`

template genIGS(n){.dirty.} =
  genGS `getUint n`, `setUint n`, `uint n`, n
  genGS `getInt n`, `setInt n`, `int n`, n
template genFGS(n){.dirty.} =
  genGS `getFloat n`, `setFloat n`, `float n`, n

genBigI int64
genBigI uint64

genIGS 32
genIGS 16
genIGS 8

genFGS 64
genFGS 32

