## inner. Only used when to debug neval.nim
import std/[strformat]
import std/[tables, sets]
import ./compile
import ../Objects/[pyobject, codeobject, hash]
import ../Utils/utils
var
  preMsg: array[3, string]
  codeVisited: HashSet[PyCodeObject]
  oldStack: seq[PyObject]

proc tostr*(s: seq[PyObject]): string =
  var res = "["
  for i, v in s:
    if i > 0: res.add ", "
    res.add:
      if v.isNil:
        "nil"
      elif v.ofPyCodeObject:
        let c = PyCodeObject(v)
        fmt"""<code object {c.codeName.str} at {c.idStr}, file "{c.fileName.str}">"""
      else:
        $v
  res.add "]"
  res

func `===`(a, b: seq[PyObject]): bool =
  for i, e in a:
    if i >= b.len: return
    if not system.`==`(e, b[i]): return
  return true

proc `$!`(c: PyCodeObject): string =
  fmt"""<visited code object {c.codeName.str} at {c.idStr}""" #, file "{c.fileName.str}">"""

proc toString(c: PyCodeObject): string =
  if DictError!(c in codeVisited):
    $!c #"(visited before)"
  else: &"<code object at {c.idStr}>\n" & $c


proc toString(s: seq[PyObject]): string =
  var res = "["
  for i, v in s:
    if i > 0: res.add ", "
    res.add:
      if v.isNil:
        "nil"
      elif v.ofPyCodeObject:
        toString(PyCodeObject(v))
      else:
        $v
  res.add "]"
  res

template debug_thisInstr* =
  bind preMsg, oldStack, codeVisited
  bind `&`
  bind `===`, `$!`, toString, toStringBy
  var thisline = ""
  for i in preMsg.mitems:
    if i.len > 0: thisline.add i
    i = ""
  echo thisline

  if not (valStack === oldStack):
    preMsg[1] = ' ' & oldStack.toString & " -> " & valStack.toString
    #for i, v in valStack: echo fmt"  [{i}]: {v}"
    oldStack = valStack
  var others: seq[PyCodeObject]
  var s = (opCode, opArg).toStringBy(f.code, others)

  preMsg[0] = s

  if others.len > 0:
    var line = "\n== Other code objects:\n"
    for i{.inject.}, c{.inject.} in others:
      line &= &"=== {i}:"
      if DictError!(c in codeVisited):
        line &= $!c # & " (visited before)\n"
        continue
      let s{.inject.} = toString(c)
      line &= &"\n {s}\n"
      DictError!!codeVisited.incl c
    preMsg[2] = line
