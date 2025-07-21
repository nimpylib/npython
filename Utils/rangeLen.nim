# nimpylib src/pylib/builtins/private/mathutils.nim
# @aca732bcf09561a6ef3a6d4957af55ec854b5045
func iPosCeil*[I: SomeInteger](x: float): I =
  ## I(ceil(x)) if x > 0 else 0
  if x > 0:
    let more = (x - float(I(x)) > 0)
    I(x) + I(more)
  else: I(0)

func rangeLen*[I](start, stop, step: I): I =
  iPosCeil[I]((stop - start) / step)
