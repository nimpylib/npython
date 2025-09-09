
import std/parseutils
from std/strutils import Digits, IdentChars
from ../Objects/numobjects/intobject/fromStrUtils import isDigitOfBase

template parseName*(s: string, res: var string, idx: var int; msg: var string): bool =
  bind parseIdent
  msg = "Invalid identifier"
  let i = parseIdent(s, res, idx)
  idx.inc i
  i != 0

proc invKind(msg: var string, kind: string) =
  msg.add "invalid "
  msg.add kind
  msg.add " literal"

proc verify_end_of_number(c: char, kind: string, msg: var string): bool =
  # XXX: NPython doesn't wanna support things like `1and xx` currently
  if c in IdentChars:
    msg.invKind kind
    return false
  return true

proc parseNumber*(s: string, res: var string, idx: var int, msg: var string): bool =
  ## Rough equal to re"\b(0[XxOoBb])?[\d_]*\.?\d+([eE][-+]?[\d_]+)?\b"
  ##
  {.push boundChecks: off.}
  let start = idx
  let hi = s.high
  template strp: untyped = s.toOpenArray(idx, hi)
  template ret =
    res = s[start..<idx]
    return
  template curOr(elseDo): untyped =
    if idx <= hi:
      s[idx]
    else:
      elseDo
  template cur: untyped = curOr(ret)

  template eatDigits =
    idx.inc strp.skipWhile Digits+{'_'}
  if cur == '0':
    idx.inc
    var c = cur
    # Hex, octal or binary -- maybe.
    template handleDigit(base: uint8; kind: string) =
      idx.inc
      c = cur
      while true:
        if c == '_':
          idx.inc
          c = cur

        if not (c.isDigitOfBase(base)):
          msg.invKind kind
          break

        result = true
        while true:
          idx.inc
          c = curOr:
            break
          if not c.isDigitOfBase(base):
            msg.invKind kind
            break

        if c != '_': break
      if not verify_end_of_number(c, kind, msg):
        ret
    case c
    of 'x', 'X': handleDigit(16, "hexdecimal")
    of 'o', 'O': handleDigit( 8, "octal")
    of 'b', 'B': handleDigit( 2, "binary")
    else:
      idx.dec
      eatDigits
  else:
    eatDigits
  result = true
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
