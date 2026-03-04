
import ./decl
import ./[ops, ops_bitwise]
import pkg/intobject/ops_mix_nim
export private_gen_mix, private_mixOpPyWithNim

private_gen_mix mix, SomeInteger, PyIntObject:
  bind op, newPyInt
  op(a, newPyInt(b))
do:
  bind op, newPyInt
  op(newPyInt(a), b)

private_mixOpPyWithNim_with_div_mod_bitwise mix, mix

when isMainModule:
  let t = newPyInt(10)
  discard t * 2
  discard t <= 2
  discard t shl 2
  discard t mod 3
