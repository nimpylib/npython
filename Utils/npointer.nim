
when defined(js):
  import npointer_js
  export npointer_js except genGS
else:
  import std/endians
  type NPointer* = pointer

  const defLittleEndian* = cpuEndian == littleEndian
  template swapEndian8(a, b) = discard
  template swapIfNeed(n, o, i; elseDo) =
    if defLittleEndian != isLittleEndian:
      `swapEndian n` o.addr, i.addr
    else: elseDo
  using d: NPointer
  template genGS*(g, s, T; n: int){.dirty.} =
    proc g*(d; i: int): T =
      (cast[ptr T](cast[int](d) + i))[]

    proc s*(d; i: int; v: T) =
      (cast[ptr T](cast[int](d) + i))[] = v

    proc g*(d; i: int; isLittleEndian: bool): T =
      let res = d.g i
      swapIfNeed n, result, res:
        result = res

    proc s*(d; i: int; v: T; isLittleEndian: bool) =
      var vv: T
      swapIfNeed n, vv, v:
        vv = v
      d.s(i, vv)
template genIGS*(n){.dirty.} =
  genGS `getUint n`, `setUint n`, `uint n`, n
  genGS `getInt n`, `setInt n`, `int n`, n
template genFGS*(n){.dirty.} =
  genGS `getFloat n`, `setFloat n`, `float n`, n
genIGS 8
genIGS 16
genIGS 32
genIGS 64

genFGS 32
genFGS 64

when isMainModule:
  var p = alloc0(4)
  echo p.repr
  echo p.getint8 0
  p.setUint16 2, 1
  echo p.getint16(2)
  dealloc p
  p = nil

