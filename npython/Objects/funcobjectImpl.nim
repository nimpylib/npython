import std/strformat

import pyobject
import ./[exceptions, tupleobject, dictobject, codeobject, stringobject, hash, generatorobject, noneobject, boolobject]
from ./exceptions/extra_utils import PyErr_CreateException
import frameobject
import funcobject

import ../Python/neval
import ../Include/cpython/compile

export funcobject

methodMacroTmpl(Function)
methodMacroTmpl(BoundMethod)

methodMacroTmpl(Generator)
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
  if code.flags & CO.GENERATOR:
    let frame = PyFrameObject(newF)
    frame.privateOwner = FRAME_OWNED_BY_GENERATOR
    return newPyGenerator(frame)
  PyFrameObject(newF).evalFrame

proc resumeGenerator(self: PyGeneratorObject): PyObject =
  if self.finished:
    return newStopIterError()
  if self.running:
    return newValueError newPyAscii("generator already executing")
  self.running = true
  let value = self.frame.evalFrame
  self.running = false
  if value.isThrownException:
    self.finished = true
    return value
  if self.frame.completed:
    self.finished = true
    return newStopIterError()
  value

implGeneratorMagic iter:
  self

implGeneratorMagic iternext:
  self.resumeGenerator

implGeneratorMethod send(value: PyObject):
  if self.finished:
    return newStopIterError()
  let frame = self.frame
  if frame.lastInstruction == -1:
    if not value.isPyNone:
      return newTypeError newPyAscii("can't send non-None value to a just-started generator")
  else:
    assert frame.valueStack.len != 0
    frame.valueStack[^1] = value
  self.resumeGenerator

genProperty Generator, "gi_code", gi_code, self.frame.code
genProperty Generator, "gi_frame", gi_frame, (if self.finished: pyNone else: self.frame)
genProperty Generator, "gi_running", gi_running, newPyBool self.running
genProperty Generator, "gi_suspended", gi_suspended,
  newPyBool(not self.finished and not self.running and self.frame.lastInstruction >= 0)

genProperty Generator, "gi_yieldfrom", gi_yieldfrom, pyNone
implGeneratorMethod close():
  if not self.finished:
    self.finished = true
    self.frame.completed = true
    self.frame.valueStack.setLen(0)
  pyNone

#TODO:exc throw(tp, value, tb)
#TODO:PyErr_NormalizeException
implGeneratorMethod throw(exc: PyObject):
  let thrown =
    if exc.ofPyExceptionClass:
      PyErr_CreateException(PyTypeObject(exc), nil)
    else:
      exc
  if not thrown.ofPyExceptionObject:
    return newTypeError newPyStr("exceptions must be classes or instances " &
                     "deriving from BaseException, not " & thrown.typeName)
  self.finished = true
  PyExceptionObject(thrown).thrown = true
  self.frame.completed = true
  self.frame.valueStack.setLen(0)
  thrown

implFunctionMagic call:
  callFunction(self, args, kwargs)

implBoundMethodMagic call:
  # merge supplied args with defaults and include self
  callFunction(self.fun, @[self.self] & @args, kwargs)
