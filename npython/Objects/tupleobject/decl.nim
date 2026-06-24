


import std/hashes
from std/sugar import collect
import ../[
  pyobject,
]
export pyobject
declarePyType Tuple(reprLock, tpToken):
  items: seq[PyObject]
  setHash: bool
  privateHash: Hash

proc newPyTuple*(): PyTupleObject{.inline.} =
  ## inner, used by  `__mul__` method
  result = newPyTupleSimple()

proc newPyTuple*[T: PyObject](items: openArray[T]): PyTupleObject{.inline.} = 
  result = newPyTuple()
  result.items = @items

template PyTuple_Collect*(body): PyTupleObject =
  ## EXT. use as std/sugar's collect.
  ## this exists as we cannot define `PyTuple_New`(which accepts int as len)
  bind collect, newPyTuple
  newPyTuple collect body

proc collectVarargsToPyObjectArr(args: NimNode): NimNode =
  result = newNimNode(nnkBracket, args)
  for i in args: result.add newCall(bindSym"PyObject", i)

macro PyTuple_Pack*(args: varargs[typed]): PyTupleObject{.inline.} =
  ## mainly used for arguments with different types
  runnableExamples:
    let i = newPyTuple()
    discard PyTuple_Pack(i, PyObject i)
  newCall(bindSym"newPyTuple", collectVarargsToPyObjectArr(args))
