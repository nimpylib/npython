
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
]
import ../Utils/[
  utils,
]
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
  # handle wrong number of args
  if code.argScopes.len < args.len:
    let msg = fmt"{fun.name.str}() takes {code.argScopes.len} positional arguments but {args.len} were given"
    return newTypeError(newPyStr msg)
  elif args.len < code.argScopes.len:
    let diff = code.argScopes.len - args.len
    let msg = fmt"{fun.name.str}() missing {diff} required positional argument: " & 
              fmt"{code.argNames[^diff..^1]}. {args.len} args are given."
    return newTypeError(newPyStr(msg))
  let frame = newPyFrame()
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
  for i in 0..<args.len:
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
  # setup closures. Note some are done when setting up arguments
  if fun.closure.isNil:
    assert code.freeVars.len == 0
  else:
    assert code.freevars.len == fun.closure.items.len
    for idx, c in fun.closure.items:
      assert c.ofPyCellObject
      frame.cellVars[code.cellVars.len + idx] = PyCellObject(c)
  frame
