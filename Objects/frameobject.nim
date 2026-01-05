
import std/strformat
import pyobject

import codeobject
import dictobject
import cellobject
import stringobject
import ./pyobject_apis/strings

declarePyType Frame():
  #TODO:frame see CPython's frame.c:take_ownership and frameobject.c:PyFrame_GetBack
  back{.member"f_back", readonly, nil2none.}: PyFrameObject
  code{.member"f_code", readonly.}: PyCodeObject
  lineno: int = -1
  # dicts and sequences for variable lookup
  # locals not used for now
  # locals*: PyDictObject
  globals{.member"f_globals", readonly.}: PyDictObject
  # builtins: PyDictObject
  fastLocals: seq[PyObject]
  cellVars: seq[PyCellObject]

proc PyUnstable_InterpreterFrame_GetLine(f: PyFrameObject): int =
  #TODO:PyFrame_GetLineNumber
  # NOTE: there're also another place storing line number info: exceptionsImpl.nim:newTraceback
  result = f.code.lineNos[0]

proc getLineNumber*(f: PyFrameObject): int =
  ## `PyFrame_GetLineNumber`
  result = f.lineno
  if result == -1:
    f.lineno = PyUnstable_InterpreterFrame_GetLine(f)
    if f.lineno < 0:
      f.lineno = 0
  if f.lineno > 0:
    return f.lineno
  else:
    return PyUnstable_InterpreterFrame_GetLine(f)

method `$`*(f: PyFrameObject): string{.raises: [].} =
  let lineno = f.getLineNumber()
  let code = f.code
  let fnObj = PyObjectRepr(code.fileName)
  assert fnObj.ofPyStrObject
  let fn = $PyStrObject(fnObj).str
  return &"<frame at {f.idStr}, file {fn}, line {lineno}, code {code.codeName}>"

implFrameMagic repr: newPyStr $self

# initialized in neval.nim
proc newPyFrame*: PyFrameObject = 
  newPyFrameSimple()

proc toPyDict*(f: PyFrameObject): PyDictObject {. cdecl .} = 
  result = newPyDict()
  let c = f.code
  for idx, v in f.fastLocals:
    if v.isNil:
      continue
    result[c.localVars[idx]] = v
  let n = c.cellVars.len
  for idx, cell in f.cellVars[0..<n]:
    assert (not cell.isNil)
    if cell.refObj.isNil:
      continue
    result[c.cellVars[idx]] = cell.refObj
  for idx, cell in f.cellVars[n..^1]:
    assert (not cell.isNil)
    if cell.refObj.isNil:
      continue
    result[c.freeVars[idx]] = cell.refObj

