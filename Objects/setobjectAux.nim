
import std/sets
import ./[
  pyobject,
  setobject,
]
export setobject

import ../Utils/[utils]
import ./numobjects/intobject/decl

type TT = PyIntObject
template gen(S){.dirty.} =
  borrowFunc1s bool, containsOrIncl, S, TT
  borrowFunc1s bool, contains, S, TT
  borrowFunc1sVoid incl, S, TT

gen Set
gen FrozenSet
