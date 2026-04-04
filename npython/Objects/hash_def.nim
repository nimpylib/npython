## this is splited for stringobject to use
import std/hashes
export Hash, `!&`, `!$`

import ../Utils/addr0

const
  MULTIPLIER* = Hash 1_000_003 # 0xf4243
  ## PyHash_MULTIPLIER Prime multiplier used in string and various other hashes.
  ##  XXX: currently no use
  IMAG* = MULTIPLIER
  INF* = hash Inf
  ALGO: cstring = "JOAAT"
  ## "`Jenkins's one-at-a-time` hash", the hash algorithm of `!&` and `!$` as well as `hashData`
  #[others:
  floats( and ints if `defined(nimIntHash1)`): "wyhash_v1" #WangYi hash V1
  strings/cstrings:
    when defined(nimStringHash2): "murmur3a"
    else: "farm"
  Values is inspected from current source code of Nim std/hashes (v2.3.1)
  )]#

type PyHash_FuncDef* = object
  ## hash function definition
  hash*: proc (p: pointer, n: int): Hash{.raises: [].}  ## like std/hashes.hashData. 
  ## Just like in CPython, only Py_HashBuffer (for str/bytes/bytearray) uses this
  name*: cstring
  hash_bits*,
    seed_bits*: int

const Py_SupHashBuffer* = not defined(js)  #XXX:NIM-BUG: js has bug to run hashData

var PyHash_Func = PyHash_FuncDef(
    hash: hashData,
    name: ALGO,
    hash_bits: 64,
    seed_bits: 8*sizeof(int),
  )
proc PyHash_GetFuncDef*: PyHash_FuncDef{.inline.} = PyHash_Func

when Py_SupHashBuffer:
  proc PyHash_SetFuncDef*(x: PyHash_FuncDef) = PyHash_Func = x
  proc Py_HashBuffer*(p: pointer, n: int): Hash{.raises: [].} = PyHash_Func.hash(p, n)
  proc Py_HashBuffer*[T](p: openArray[T]): Hash = Py_HashBuffer(p.addr0, p.len * sizeof T)
else:
  const notSup = "set Py_HashBuffer is not supported in this platform"
  proc PyHash_SetFuncDef*(x: PyHash_FuncDef){.error: notSup.}
  proc Py_HashBuffer*(p: pointer, n: int): Hash{.raises: [], error: notSup.}
  proc Py_HashBuffer*[T](p: openArray[T]): Hash =
    for i in p:
      result = result !& cast[int](i)
    result = !$result

