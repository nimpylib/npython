
import ./decl
import ./[ops, ops_bitwise]
#[ XXX:NIM-BUG: not works:
import std/macros
macro private_mixOpPyIntWithNim*{(`+`|`-`|`*`|`div`|`mod`){op}(a, b)}(
  a: PyIntObject, op: untyped, b: SomeInteger): untyped =
  quote do: `op` `a`, newPyInt(`b`)
]#

template private_gen_mix*(mix; prim, pyT: typedesc; do1, do2){.dirty.} =
  template mix(op){.dirty.} =
    template `op`*(a: pyT, b: prim): untyped = do1
    template `op`*(a: prim, b: pyT): untyped = do2

private_gen_mix mix, SomeInteger, PyIntObject:
  bind op, newPyInt
  op(a, newPyInt(b))
do:
  bind op, newPyInt
  op(newPyInt(a), b)

template private_mixOpPyWithNim*(mixb, mix){.dirty.} =
  mixb `==`
  mixb `<`
  mixb `<=`

  mix `+`
  mix `-`
  mix `*`
  # mix `div`
  # mix `mod`
  mix `%`
  mix `//`

  mix divmod
  mix pow


private_mixOpPyWithNim mix, mix
mix `div`
mix `mod`

mix `and`
mix `or`
mix `xor`
mix `shl`
mix `shr`

when isMainModule:
  let t = newPyInt(10)
  discard t * 2
  discard t <= 2
  discard t shl 2
  discard t mod 3
