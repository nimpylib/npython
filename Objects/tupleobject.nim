
import std/hashes
import ./pyobject

declarePyType Tuple(reprLock, tpToken):
  items: seq[PyObject]
  setHash: bool
  privateHash: Hash


proc newPyTuple*(): PyTupleObject{.inline.} =
  ## inner, used by  `__mul__` method
  result = newPyTupleSimple()

proc newPyTuple*(items: seq[PyObject]): PyTupleObject = 
  result = newPyTuple()
  # shallow copy
  result.items = items

proc newPyTuple*(items: openArray[PyObject]): PyTupleObject{.inline.} = 
  newPyTuple @items  