
import std/strformat
import ./[
  symtable,
]
import ../Objects/[pyobject,
  funcobject,
  cellobject,
  codeobject, frameobject,
  exceptions,
  stringobject,
  noneobject,
]
import ../Utils/[
  utils,
]
#TODO:interpreters
var gFrame{.threadVar.}: PyFrameObject
proc PyEval_GetFrame*(): PyFrameObject = gFrame
proc PyEval_GetGlobals*: PyObject =
  if gFrame.isNil: nil
  else: gFrame.globals

proc newPyFrame*(fun: PyFunctionObject, 
                 args: openArray[PyObject], 
                 back: PyFrameObject): PyObject{.raises: [].}

proc newPyFrame*(fun: PyFunctionObject): PyFrameObject = 
  let obj = newPyFrame(fun, @[], nil)
  if obj.isThrownException:
    unreachable
  else:
    return PyFrameObject(obj)

proc newPyFrame*(fun: PyFunctionObject, 
                 args: openArray[PyObject], 
                 back: PyFrameObject): PyObject{.raises: [].} =
  let code = fun.code
  # handle vararg: allow last arg to be vararg tuple when code.varArgName is present
  var provided = args.len
  var varargTuple: PyObject = nil
  if not code.varArgName.isNil and args.len == code.argCount + 1:
    varargTuple = args[^1]
    provided = args.len - 1
  # handle wrong number of args
  if code.argCount < provided:
    let msg = fmt"{fun.name.str}() takes {code.argCount} positional arguments but {provided} were given"
    return newTypeError(newPyStr msg)
  elif provided < code.argCount:
    let diff = code.argCount - provided
    let msg = fmt"{fun.name.str}() missing {diff} required positional argument: " & 
              fmt"{code.argNames[^diff..^1]}. {provided} args are given."
    return newTypeError(newPyStr(msg))
  let frame = newPyFrame()
  gFrame = frame
  frame.back = back
  frame.code = code
  frame.globals = fun.globals
  # todo: use flags for faster simple function call
  frame.fastLocals = newSeq[PyObject](code.localVars.len)
  frame.cellVars = newSeq[PyCellObject](code.cellVars.len + code.freeVars.len)
  # init cells. Can do some optimizations here
  for i in 0..<code.cellVars.len:
    frame.cellVars[i] = newPyCell(nil)
  # setup arguments
  for i in 0..<provided:
    let (scope, scopeIdx) = code.argScopes[i]
    case scope
    of Scope.Local:
      frame.fastLocals[scopeIdx] = args[i]
    of Scope.Global:
      unreachable
    of Scope.Cell:
      frame.cellVars[scopeIdx].refObj = args[i]
    of Scope.Free:
      unreachable("arguments can't be free")
  # assign vararg tuple to its local if present
  if not code.varArgName.isNil and not varargTuple.isNil:
    # find local index for varArgName
    var varIdx = -1
    for i, name in code.localVars:
      if name == code.varArgName:
        varIdx = i
        break
    if varIdx >= 0:
      frame.fastLocals[varIdx] = varargTuple
  # setup closures. Note some are done when setting up arguments
  if fun.closure.isNil:
    assert code.freeVars.len == 0
  else:
    assert code.freevars.len == fun.closure.items.len
    for idx, c in fun.closure.items:
      assert c.ofPyCellObject
      frame.cellVars[code.cellVars.len + idx] = PyCellObject(c)
  # apply kw-only defaults if any
  if code.kwOnlyNames.len > 0:
    for i, name in code.kwOnlyNames:
      # find local index
      var localIdx = -1
      for j, ln in code.localVars:
        if ln == name:
          localIdx = j
          break
      if localIdx >= 0 and frame.fastLocals[localIdx].isNil:
        if i < code.kwOnlyDefaults.len:
          frame.fastLocals[localIdx] = code.kwOnlyDefaults[i]
        else:
          frame.fastLocals[localIdx] = pyNone
  frame
