
import std/macros
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

proc newPyTuple*[T: PyObject](items: openArray[T]): PyTupleObject{.inline.} = 
  newPyTuple @items

template toPyObject(x: PyObject): PyObject = x
proc collectVarargsToPyObjectArr(args: NimNode): NimNode =
  result = newNimNode(nnkBracket, args)
  for i in args: result.add newCall(bindSym"toPyObject", i)

macro PyTuple_Pack*(args: varargs[typed]): PyTupleObject{.inline.} =
  ## mainly used for arguments with different types
  runnableExamples:
    let i = newPyTuple()
    discard PyTuple_Pack(i, PyObject i)
  newCall(bindSym"newPyTuple", collectVarargsToPyObjectArr(args))
