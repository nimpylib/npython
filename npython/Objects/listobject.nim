import std/[sequtils, algorithm]
import std/[strutils, strformat]

import ./pyobject
import ./[
  exceptions, stringobject, noneobject,
  iterobject, tupleobject, dictobject,
]
import ./numobjects/intobject/[decl, signbit, ops_mix_nim, ops_toint]

import ./hash
import ../Utils/compat

declarePyType List(reprLock, mutable, tpToken, typeName("list")):
  items: seq[PyObject]


proc newPyList*: PyListObject = 
  newPyListSimple()

proc newPyList*(items: sink seq[PyObject]): PyListObject =
  result = newPyList()
  result.items = items

proc newPyList*(len: int): PyListObject =
  ## PyList_New
  newPyList newSeq[PyObject](len)

proc newPyList*(items: openArray[PyObject]): PyListObject = 
  newPyList @items

proc toPyTuple*(tup: PyListObject): PyTupleObject =
  ## PyList_AsTuple
  newPyTuple tup.items

template lsSeqToStr(ss): string = '[' & ss.join", " & ']'

genCollectMagics items,
  implListMagic,
  ofPyListObject, PyListObject,
  [mutable: read], [reprLockWithMsg"[...]", mutable: read],
  lsSeqToStr

proc add*(self: PyListObject, o: PyObject) = self.items.add o
template genMutableSequenceMethods_NotDepWarn*(mapper, unmapper, S, Ele, beforeAppend){.dirty.} =
  ## `beforeAppend` body will be inserted before `append` method's implementation
  bind reverse
  bind unhashable, delete
  bind pyForIn, toIntOrRetOF
  bind echoCompat
  proc extend*(self: `Py S Object`, other: PyObject): PyObject =
    if other.`ofPy S Object`:
      self.items &= `Py S Object`(other).items
    else:
      pyForIn nextObj, other:
        self.items.add nextObj.mapper
    pyNone


  `impl S Magic` iadd, [mutable: write]: self.extend other

  
  proc `[]=`*(self: `Py S Object`; i: int, v: Ele){.inline.} = self.items[i] = v
  proc `[]=`*(self: `Py S Object`; i: HSlice, v: seq[Ele]){.inline.} = self.items[i] = v

  `impl S Magic` hash: unhashable self

  when not compiles((var temp:`Py S Object`; temp.add temp)):
    proc add*(self: `Py S Object`, item: PyObject): PyObject =
      beforeAppend
      self.items.add(item.mapper)
      pyNone
  proc append*(self: `Py S Object`, item: PyObject): PyObject =
    beforeAppend
    self.items.add(item.mapper)
    pyNone

  `impl S Method` append(item: PyObject), [mutable: write]: self.append item

  `impl S Method` clear(), [mutable: write]:
    self.items.setLen 0
    pyNone

  `impl S Method` reverse(), [mutable: write]:
    reverse(self.items)
    pyNone

  `impl S Method` copy(), [mutable: read]:
    let newL = `newPy S`()
    newL.items = self.items # shallow copy
    newL


  # some test methods just for debugging
  when not defined(release):
    # for lock testing
    `impl S Method` doClear(), [mutable: read]:
    # should fail because trying to write while reading
      self.`clearPy S ObjectMethod`()

    `impl S Method` doRead(), [mutable: write]:
      # trying to read while writing
      return self.`doClearPy S ObjectMethod`()


    when Ele is PyObject:
      # for checkArgTypes testing
      `impl S Method` aInt(i: PyIntObject), [mutable: read]:
        self.items.add(i)
        pyNone

      # for macro pragma testing
      macro hello(code: untyped): untyped = 
        code.body.insert(0, nnkCommand.newTree(bindSym("echoCompat"), newStrLitNode("hello")))
        code

      `impl S Method` hello(), [hello]:
        pyNone


  `impl S Method` extend(other: PyObject), [mutable: write]: self.extend other


  `impl S Method` insert(idx: PyIntObject, item: PyObject), [mutable: write]:
    var intIdx: int
    if idx.negative:
      intIdx = 0
    elif self.items.len < idx:
      intIdx = self.items.len
    else:
      intIdx = idx.toIntOrRetOF
    self.items.insert(item.mapper, intIdx)
    return pyNone


  `impl S Method` pop(), [mutable: write]:
    if self.items.len == 0:
      let msg = "pop from empty list"
      return newIndexError newPyAscii(msg)
    unmapper self.items.pop


template asIs(x): untyped = x
genMutableSequenceMethods_NotDepWarn(asIs, asIs, List, PyObject): discard
