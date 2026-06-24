

import ./consts
import std/sets

template genIs(name, ls) {.dirty.} =
  const name = toHashSet ls

  proc `is name`*(x: string): bool = x in name

genIs keyword, kwlist
genIs softkeyword, softkwlist

