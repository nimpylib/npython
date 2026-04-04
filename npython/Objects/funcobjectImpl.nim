import pyobject
import ./[exceptions, tupleobject, codeobject]
import frameobject
import funcobject

import ../Python/neval

export funcobject

methodMacroTmpl(Function)
methodMacroTmpl(BoundMethod)

proc callFunction(funcObj: PyFunctionObject, args: openArray[PyObject], kwargs: PyObject, prevF: PyFrameObject = nil): PyObject =
  #TODO
  assert kwargs.isNil, "Calling python non-builtin function with keyword is not implemented yey"

  # todo: eliminate the nil
  # merge defaults for missing positional args before creating frame
  let code = funcObj.code
  var newF: PyObject

  # if function has vararg, pack extra positional args into tuple and pass fewer positional args
  # detect vararg either from code.varArgName or by presence of additional localVar slot
  
  block initNewFrame:
    let provided = args.len          
    let argCount = code.argCount

    var allowVarArg = not code.varArgName.isNil
    #if not allowVarArg and code.localVars.len > fixedCount: allowVarArg = true
    let argsNotEnough = provided < argCount
    if not allowVarArg and not argsNotEnough:
      # enough args provided, no vararg
      newF = newPyFrame(funcObj, args, prevF)
      break initNewFrame
    var finalArgsSeq = newSeq[PyObject](argCount)
    var varTuple: PyTupleObject

    var nArgsToFinal: int
    if argsNotEnough:
      # missing required positional before vararg: handle defaults if any
      let need = argCount - provided
      if funcObj.defaults.isNil or funcObj.defaults.len < need:
        newF = newPyFrame(funcObj, args, prevF)
        break initNewFrame
      let dlen = funcObj.defaults.len
      for i in 0..<need:
        finalArgsSeq[provided + i] = funcObj.defaults[dlen - need + i]
      # build vararg tuple from remaining args (none)
      if allowVarArg:
        varTuple = newPyTuple()
      nArgsToFinal = provided
    else:
      # enough args provided
      if not allowVarArg:
        newF = newPyFrame(funcObj, args, prevF)
        break initNewFrame
      # pack extra args into vararg tuple
      var varArgs = newSeq[PyObject](provided - argCount)
      for i in 0..<varArgs.len:
        varArgs[i] = args[argCount + i]
      varTuple = newPyTuple(varArgs)
      nArgsToFinal = argCount

    for i in 0..<nArgsToFinal: finalArgsSeq[i] = args[i]
    if allowVarArg:
      # build final args seq of fixedCount + 1 (vararg)
      finalArgsSeq.add varTuple
    newF = newPyFrame(funcObj, finalArgsSeq, prevF)

  retIfExc newF
  return PyFrameObject(newF).evalFrame

implFunctionMagic call:
  callFunction(self, args, kwargs)

implBoundMethodMagic call:
  # merge supplied args with defaults and include self
  callFunction(self.fun, @[self.self] & @args, kwargs)
