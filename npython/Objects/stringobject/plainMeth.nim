

import ../[stringobject, exceptions]
import ./helpers
import ../../Utils/[sequtils, sequtils2]

template gen_find(find){.dirty.} =

  proc find*(self: UnicodeVariant, target: char, start=0, stop=self.len): int =
    prefind
    if self.ascii: find(self.asciiStr, target, start, stop)
    else: find(self.unicodeStr, Rune target, start, stop)

  proc find*(self: PyStrObject, target: char, start=0, stop=self.len): int = prefind; self.str.find(target, start, stop)

gen_find find
gen_find rfind

proc substringUnsafe*(self: PyStrObject, start, stop: int): PyStrObject =
  ## `PyUnicode_Substring`
  ##
  ## Nim's `self.substr[start, stop+1]`
  ## 
  ## assert start >= 0 and stop >= 0
  let
    len = self.len
    stop = min(stop, len)

  if start == 0 and stop == len:
    return self  # unchanged
  assert not (start < 0 or stop < 0)
    
  if start >= len or stop < start:
    return newPyAscii()
  if self.isAscii:
    newPyString self.data.asciiStr[start ..< stop]
  else:
    newPyString self.data.unicodeStr[start ..< stop]

proc substring*(self: PyStrObject, start, stop: int, res: var PyStrObject): PyIndexErrorObject =
  if start < 0 or stop < 0:
    return newIndexError newPyAscii "string index out of range"
  res = self.substringUnsafe(start, stop)
