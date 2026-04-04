
import std/strformat
import pyobject

import codeobject
import dictobjectImpl
import cellobject
import ./stringobject/strformat
import ./[
  byteobjects,
  #boolobject,
  listobject,
  stringobject,
  exceptions,
]
import ./pyobject_apis/strings
import ./abstract/iter
import ../Include/cpython/[critical_section, compile]
import ../Include/internal/pycore_interpframe_struct
export PyInterpFrameOwner

declarePyType Frame(mutable):
  #TODO:frame see CPython's frame.c:take_ownership and frameobject.c:PyFrame_GetBack
  back{.member"f_back", readonly, nil2none.}: PyFrameObject
  code{.member"f_code", readonly.}: PyCodeObject
  lineno: int = -1
  # dicts and sequences for variable lookup
  # locals not used for now,
  #   so PEP 667 not implemented
  #   f_locals is accessed via a proxy object, see below
  # locals{.member"f_locals", readonly.}: PyObject
  globals{.member"f_globals", readonly.}: PyDictObject
  # builtins: PyDictObject
  fastLocals: seq[PyObject]
  cellVars: seq[PyCellObject]
  owner{.private.}: PyInterpFrameOwner

func privateOwner*(f: PyFrameObject): var PyInterpFrameOwner{.inline.} =
  ## internal, term to change
  result = f.owner

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
  return &"<frame at {f.idStr}, file {fn}, line {lineno}, code {$code.codeName}>"

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

declarePyType FrameLocalsProxy(reprLock):
  frame: PyFrameObject

proc newPyFrameLocalsProxy*(frame: PyFrameObject): PyFrameLocalsProxyObject =
  result = newPyFrameLocalsProxySimple()
  result.frame = frame

implFrameLocalsProxyMagic New(frame):
  if not frame.ofPyFrameObject:
    return newTypeError newPyStr "expect frame, not " & frame.typeName
  return newPyFrameLocalsProxy PyFrameObject(frame)

const hasLocalDict = compiles(PyFrameObject.locals)

proc getval*(self: PyFrameObject, co: PyCodeObject, i: int): PyObject =
  when hasLocalDict:
    result = self.fastLocals[i]#PyStackRef_AsPyObjectBorrow(fast[i])
    let kind: PyLocals_Kind = co.co_localspluskinds.getKind i

    var cell: PyObject = nil

    if result.isNil:
      return

    if kind == CO_FAST_FREE or (kind and CO_FAST_CELL):
      # // The cell was set when the frame was created from
      # // the function's closure.
      # // GH-128396: With PEP 709, it's possible to have a fast variable in
      # // an inlined comprehension that has the same name as the cell variable
      # // in the frame, where the `kind` obtained from frame can not guarantee
      # // that the variable is a cell.
      # // If the variable is not a cell, we are okay with it and we can simply
      # // return the value.
      if result.ofPyCellObject:
        cell = result

    if cell != nil:
      result = PyCellObject(cell)
  else:
    var n: int
    var ii = i
    n = self.fastLocals.len
    if ii < n:
      return self.fastLocals[i]
    ii -= n
    assert ii < co.cellVars.len + co.freeVars.len
    let cell = self.cellVars[ii]
    assert (not cell.isNil)
    return cell.refObj


proc hasval*(self: PyFrameObject, co: PyCodeObject, i: int): bool = getval(self, co, i) != nil

proc keys*(self: PyFrameLocalsProxyObject): PyObject{.pyCFuncPragma.} =
  let names = newPyList();

  let frame = self.frame
  let co = frame.code
  when hasLocalDict:
    if self.hasval(frame, co, 0):
      for i in 0..<co.co_nlocalsplus:
        if hasval(frame.f_frame, co, i):
          let name = co.co_localsplusnames[i]
          retIfExc names.append(name)

    # Iterate through the extra locals
    if not frame.f_extra_locals.isNil:
      assert(ofPyDictObject(frame.f_extra_locals));

      for k in PyDictObject(frame.f_extra_locals):
        retIfExc names.append(k)
  else:
    for idx, v in frame.fastLocals:
      if v.isNil:
        continue
      retIfExc names.append co.localVars[idx]
    let n = co.cellVars.len
    for idx, cell in frame.cellVars[0..<n]:
      assert (not cell.isNil)
      if cell.refObj.isNil:
        continue
      retIfExc names.append co.cellVars[idx]
    for idx, cell in frame.cellVars[n..^1]:
      assert (not cell.isNil)
      if cell.refObj.isNil:
        continue
      retIfExc names.append co.freeVars[idx]

  return names

implFrameLocalsProxyMethod keys: self.keys()
implFrameLocalsProxyMagic getitem:
  let frame = self.frame
  template retNotFound = return newKeyError(
        PyStrFmt&"local variable '{other:R}' is not defined")
  if not other.ofPyStrObject:
    retNotFound
  when hasLocalDict:
    if not frame.f_extra_locals.isNil:
      assert(ofPyDictObject(frame.f_extra_locals))

      var exc: PyBaseErrorObject
      case PyDictObject(frame.f_extra_locals).getItemRef(other, result, exc)
      of Error: return exc
      of Missing: retNotFound
      of Got:
        return
  else:
    let key = PyStrObject other
    let co = frame.code
    var idx = co.localVars.find key
    if idx != -1:
      return frame.fastLocals[idx]
    # Okay not in the fast locals, try extra locals
    idx = co.cellVars.find key
    if idx < 0:
      retNotFound
    if idx < co.cellVars.len:
      return frame.cellVars[idx]
    idx -= co.cellVars.len
    assert idx < co.freeVars.len
    let cell = frame.cellVars[idx]
    assert (not cell.isNil)
    return cell.refObj

when hasLocalDict:
 implFrameLocalsProxyMagic contains:
  let dummy = self.getitemPyFrameLocalsProxyObjectMagic(other)
  if dummy.ofPyKeyErrorObject:
    pyFalseObj
  elif dummy.isThrownException:
    dummy
  else:
    pyTrueObj

  #implFrameLocalsProxyMagic setitem:

implFrameLocalsProxyMagic iter:
  let keys = self.keys
  PyObject_GetIter(keys)

implFrameLocalsProxyMagic repr, [reprLockWithMsg("{...}")]:
  let dct = newPyDict()
  retIfExc dct.updateImpl self
  PyObject_Repr(dct)

when hasLocalDict:
  declareIntFlag PyLocals_Kind:
    CO_FAST_ARG_POS 0x02  # pos-only, pos-or-kw, varargs
    CO_FAST_ARG_KW  0x04  # kw-only, pos-or-kw, varkwargs
    CO_FAST_ARG_VAR 0x08  # varargs, varkwargs
    CO_FAST_ARG (CO_FAST_ARG_POS.ord or CO_FAST_ARG_KW.ord or CO_FAST_ARG_VAR.ord)
    CO_FAST_HIDDEN  0x10
    CO_FAST_LOCAL   0x20
    CO_FAST_CELL    0x40
    CO_FAST_FREE    0x80

  proc getKind*(kinds: PyBytesObject, i: int): PyLocals_Kind =
    ## `_PyLocals_GetKind`
    #assert(PyBytes_Check(kinds));
    assert(0 <= i and i < len(kinds))
    return PyLocals_Kind(kinds[i])


  proc hasHiddenLocals(frame: PyFrameObject): bool =
      ##[ `_PyFrame_HasHiddenLocals`
      * This function returns if there are hidden locals introduced by PEP 709,
      * which are the isolated fast locals for inline comprehensions
      */]##
      let co = frame.code
      for i in 0..<co.nlocals: #co.nlocalsplus:
        let kind = getKind(co.localspluskinds, i)
        if (kind & CO_FAST_HIDDEN):
          if hasval(frame, co, i):
            return true

proc common_getLocalsImpl_frame_locals_get_impl(self: PyFrameObject): PyObject =
  ## `_PyFrame_GetLocals`
  #  `frame_locals_get_impl`
  #assert(!_PyFrame_IsIncomplete(self->f_frame));

  when hasLocalDict:
    let co = self.code
    if not (co.flags & CO.OPTIMIZED) and not hasHiddenLocals(self):
      if co.locals.isNil:
        # // We found cases when f_locals is NULL for non-optimized code.
        # // We fill the f_locals with an empty dict to avoid crash until
        # // we find the root cause.
        self.locals = newPyDict()
      return self.locals

  result = newPyFrameLocalsProxy(self)

proc getLocalsImpl*(self: PyFrameObject): PyObject{.pyCFuncPragma.} =
  ## `_PyFrame_GetLocals`
  #  `frame_locals_get_impl`
  self.common_getLocalsImpl_frame_locals_get_impl()

proc frame_locals_get(self: PyFrameObject): PyObject =
  criticalRead(self):
    result = self.common_getLocalsImpl_frame_locals_get_impl()

genProperty Frame, "f_locals", f_locals, self.frame_locals_get

template isIncomplete(f): bool = false #TODO:frame
proc getLocals*(self: PyFrameObject): PyObject{.cdecl.} =
  ## `PyFrame_GetLocals`
  assert not self.isIncomplete
  self.frame_locals_get()

