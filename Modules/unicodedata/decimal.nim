
from std/algorithm import upperBound
import std/enumerate
import ./rune_decl
import ./private/consts

template decimalImpl(r: Rune; result: var int; ret) =
  let ir = int r
  let upperIdx = allZeros.upperBound(ir)
  if upperIdx > 0:
    # not too small
    let idx = upperIdx - 1
    result = ir - allZeros[idx]
    if result < 10: ret
    assert result >= 0

template ret = return
proc decimal*(r: Rune, default: int): int{.raises: [].} =
  decimalImpl r, result, ret
  return default

proc decimal*(r: Rune): range[0..9]{.raises: [ValueError].} =
  decimalImpl r, result, ret
  raise newException(ValueError, "not a decimal")

template decimalItOr*(r: Rune; doIt; fallback){.dirty.} =
  ## be faster than:
  ## ```Nim
  ## let it = decimal(r, -1)
  ## if it < 0: fallback
  ## else: doIt
  ## ```
  runnableExamples:
    import std/unicode
    decimalItOr(Rune 49):
      echo it, ": a decimal"
    do:
      echo "not a decimal"
  bind decimalImpl
  block decimalItOrBlk:
    var it: int
    template ret =
      doIt
      break decimalOrBlk
    block decimalOrBlk:
      decimalImpl r, it, ret
      fallback

iterator allDecimal*(i: range[0..9]): Rune =
  ## unstable
  for d in allZeros:
    yield Rune(d+i)

proc allDecimals*(i: range[0..9]): seq[Rune] =
  ## unstable
  runnableExamples:
    import std/unicode
    let threes = allDecimals(3)
    assert threes[0] == Rune'3'
    assert threes[67] == "🯳".toRunes[0]
  result = (when declared(newSeqUninit): newSeqUninit else: newSeq)[Rune](allZeros.len)
  for idx, r in enumerate(allDecimal(i)):
    result[idx] = r

when isMainModule:
  # dump decimals table
  import std/unicode
  for n in 0..9:
    var res = $n & ": "
    for i in allDecimal(n):
      res.add $i
      res.add ' '
    echo res
