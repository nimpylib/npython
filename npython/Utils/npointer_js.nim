
import std/jsffi
type
  ArrayBuffer{.importjs.} = JsObject
  DataView{.importjs.} = JsObject
  NPointer* = DataView  ## XXX: impl is unstable, later maybe `ref object`

template genNew(T, A1){.dirty.} =
  proc `new T`(a: A1): T{.importjs: "new " & $T & "(#)".}
genNew DataView, ArrayBuffer
using n: int
genNew ArrayBuffer, int
proc alloc0*(n): NPointer = newDataView newArrayBuffer(n)
template a0alias(name){.dirty.} =
  proc name*(n): NPointer = alloc0 n
a0alias alloc
# JS is single-threaded
a0alias allocShared
a0alias allocShared0
using p: NPointer
proc dealloc*(p) = discard
proc deallocShared*(p) = discard

proc repr*(d: DataView): string = "[object DataView]"
#proc repr*(d: NPointer): string = "[object]"
const defLittleEndian* = false  # either is ok, we currently use bigEndian as in network such is used
template genGS*(g, s, T, n){.dirty.} =
  bind DataView
  proc g*(d: DataView; i: int; isLittleEndian = defLittleEndian): T{.importcpp.}
  proc s*(d: DataView; i: int; v: T; isLittleEndian = defLittleEndian){.importcpp.}

