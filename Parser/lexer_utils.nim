
from std/strutils import Digits, IdentChars
import std/parseutils

template parseName*(s: string, res: var string, start=0): bool =
  bind parseIdent
  parseIdent(s, res, start) != 0

proc parseNumber*(s: string, res: var string, start=0): bool =
  ## r"\b\d*\.?\d+([eE][-+]?\d+)?\b"
  {.push boundChecks: off.}
  let hi = s.high
  template strp: untyped = s.toOpenArray(idx, hi)
  template ret =
    idx.dec
    res = s[start..idx]
    return
  template cur: untyped =
    if idx <= hi:
      s[idx]
    else:
      ret
  result = true
  var idx = start
  template eatDigits =
    idx.inc strp.skipWhile Digits
  eatDigits
  if cur != '.': ret
  idx.inc
  eatDigits
  if cur not_in {'e', 'E'}: ret
  idx.inc
  if cur in {'+', '-'}: idx.inc
  eatDigits
  if idx < hi and s[idx+1] in IdentChars:
    result = false
  ret
  {.pop.}