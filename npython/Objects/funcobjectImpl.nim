import std/strformat

import pyobject
import ./[exceptions, tupleobject, dictobject, codeobject, stringobject, hash]
import frameobject
import funcobject

import ../Python/neval

export funcobject

methodMacroTmpl(Function)
methodMacroTmpl(BoundMethod)

proc callFunction(funcObj: PyFunctionObject, args: openArray[PyObject], kwargs: PyObject, prevF: PyFrameObject = nil): PyObject =
  let code = funcObj.code
  let argCount = code.argCount
  let provided = args.len
  let allowVarArg = not code.varArgName.isNil
  var finalArgsSeq = newSeq[PyObject](argCount)
  let kwDict =
    if kwargs.isNil:
      PyDictObject nil
    elif kwargs.ofPyDictObject:
      PyDictObject kwargs
    else:
      return newTypeError newPyAscii"keyword arguments must be a dict"

  if not kwDict.isNil:
    var hasOnlyStringKeys: bool
    handleHashExc:
      hasOnlyStringKeys = kwDict.hasOnlyStringKeys
    if not hasOnlyStringKeys:
      return newTypeError newPyAscii"keywords must be strings"

  for i in 0..<min(provided, argCount):
    finalArgsSeq[i] = args[i]

  if not kwDict.isNil:
    handleHashExc:
      for key, value in kwDict:
        let keyStr = PyStrObject key
        var matched = false
        for i, argName in code.argNames:
          if argName == key:
            if not finalArgsSeq[i].isNil:
              return newTypeError newPyStr(
                fmt"{funcObj.name.str}() got multiple values for argument '{keyStr.str}'")
            finalArgsSeq[i] = value
            matched = true
            break
        if matched:
          continue
        for kwName in code.kwOnlyNames:
          if kwName == key:
            matched = true
            break
        if not matched:
          return newTypeError newPyStr(
            fmt"{funcObj.name.str}() got an unexpected keyword argument '{keyStr.str}'")

  if provided > argCount:
    if not allowVarArg:
      return newTypeError newPyStr(
        fmt"{funcObj.name.str}() takes {argCount} positional arguments but {provided} were given")
    var varArgs = newSeq[PyObject](provided - argCount)
    for i in 0..<varArgs.len:
      varArgs[i] = args[argCount + i]
    finalArgsSeq.add newPyTuple(varArgs)
  elif allowVarArg:
    finalArgsSeq.add newPyTuple()

  for i in 0..<argCount:
    if finalArgsSeq[i].isNil:
      let missing = argCount - i
      if funcObj.defaults.isNil or funcObj.defaults.len < missing:
        return newTypeError newPyStr(
          fmt"{funcObj.name.str}() missing required positional argument '{code.argNames[i].str}'")
      finalArgsSeq[i] = funcObj.defaults[funcObj.defaults.len - missing]

  let newF = newPyFrame(funcObj, finalArgsSeq, prevF, kwDict)
  retIfExc newF
  PyFrameObject(newF).evalFrame

implFunctionMagic call:
  callFunction(self, args, kwargs)

implBoundMethodMagic call:
  # merge supplied args with defaults and include self
  callFunction(self.fun, @[self.self] & @args, kwargs)
