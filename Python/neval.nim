
import strformat
import tables
import std/sets
import compile
import symtable
import opcode
import coreconfig
import builtindict
import traceback
import ../Objects/[pyobject, baseBundle, tupleobject, listobject, dictobject,
                   sliceobject, codeobject, frameobject, funcobject, cellobject,
                   setobject, notimplementedobject, boolobjectImpl,
                   exceptionsImpl, moduleobject, methodobject]
import ../Utils/utils

type
  # the exception model is different from CPython. todo: Need more documentation
  # when the model is finished
  #
  # States of the tryblock, currently only Try(default) and Except is used
  TryStatus {. pure .} = enum
    Try,
    Except,
    Else,
    Finally

  TryBlock = ref object
    status: TryStatus
    handler: int
    sPtr: int
    context: PyExceptionObject
    

# forward declarations
proc newPyFrame*(fun: PyFunctionObject): PyFrameObject 
proc newPyFrame*(fun: PyFunctionObject, 
                 args: seq[PyObject], 
                 back: PyFrameObject): PyObject
proc evalFrame*(f: PyFrameObject): PyObject
proc pyImport*(name: PyStrObject): PyObject


template doUnary(opName: untyped) = 
  let top = sTop()
  let res = top.callMagic(opName, handleExcp=true)
  sSetTop res

macro tryCallInplaceMagic(op1, opName, op2): untyped =
  let iMagic = ident 'i' & opName.strVal
  quote do:
    `op1`.callInplaceMagic(`iMagic`, `op2`, handleExcp=false)

template doInplace(opName: untyped) =
  bind callInplaceMagic
  let op2 = sPop()
  let op1 = sTop()
  let res = op1.tryCallInplaceMagic(opName, op2)
  if res.isNotImplemented:
    var nres = op1.callMagic(opName, op2, handleExcp=true)
    if nres.isNotImplemented:
      let
        opStr{.inject.} = "i" & astToStr(opName)
        # PY-DIFF: not iadd, but +=
        typ1{.inject.} = op1.pyType.name
        typ2{.inject.} = op2.pyType.name
      nres = newTypeError newPyStr(
        &"unsupported operand type(s) for '{opStr}': '{typ1}' and '{typ2}'"
      )
      sSetTop nres
    else:
      sSetTop nres
      let stIdx = lastI - 2
      let (opCode, opArg) = f.code.code[stIdx]
      var st: OpCode
      case opCode
      of OpCode.LoadFast: st=StoreFast
      of OpCode.LoadGlobal: st=StoreGlobal
      of OpCode.LoadAttr: st=StoreAttr
      of OpCode.LoadName: st=StoreName
      of OpCode.LoadDeref: st=StoreDeref
      of {OpCode.LoadClosure, LoadMethod, LoadClassDeref}:
        raiseAssert(
          &"augumented assignment for {opCode} is not implemented yet")
      else: unreachable()
      f.code.code.insert (st, opArg), lastI+1
  else:
    sSetTop res

template doBinary(opName: untyped) =
  let op2 = sPop()
  let op1 = sTop()
  let res = op1.callMagic(opName, op2, handleExcp=true)
  sSetTop res

# the same as doBinary, but need to rotate!
template doBinaryContain: PyObject = 
  let op1 = sPop()
  let op2 = sTop()
  let res = op1.callMagic(contains, op2, handleExcp=true)
  res

# "fast" because check if it's a bool object first and save the callMagic(bool)
template getBoolFast(obj: PyObject): bool = 
  PyObject_IsTrue(obj)

# if declared as a local variable, js target will fail. See gh-10651
when defined(js):
  var valStack: seq[PyObject]
  var blockStack: seq[TryBlock]

proc evalFrame*(f: PyFrameObject): PyObject = 
  # instructions are fetched so frequently that we should build a local cache
  # instead of doing tons of dereference

  var lastI = -1

  # instruction helpers
  template fetchInstr: (OpCode, OpArg) = 
    inc lastI
    f.code.code[lastI]

  template jumpTo(i: int) = 
    lastI = i - 1

  proc setTraceBack(excp: PyExceptionObject) = 
    let lineNo = f.code.lineNos[lastI]
    # for exceptions happened when evaluating the frame no colNo is set
    excp.traceBacks.add (PyObject f.code.fileName, PyObject f.code.codeName, lineNo, -1)
   
  # in future, should get rid of the abstraction of seq and use a dynamically
  # created buffer directly. This can reduce time cost of the core neval function
  # by 25%
  when not defined(js):
    var valStack: seq[PyObject]

  # retain these templates for future optimization
  template sTop: PyObject = 
    valStack[^1]

  template sPop: PyObject = 
    valStack.pop

  template sPeek(idx: int): PyObject = 
    valStack[^idx]

  template sSetTop(obj: PyObject{atom}) = 
    when defined(debug):
      assert(not obj.pyType.isNil)
    valStack[^1] = obj
  template sSetTop(obj: PyObject) = 
    let o = obj
    sSetTop o

  template sPush(obj: PyObject{atom}) = 
    when defined(debug):
      assert(not obj.pyType.isNil)
    valStack.add obj
  template sPush(obj: PyObject) = 
    let o = obj
    sPush o

  template sEmpty: bool = 
    valStack.len == 0

  template sLen: int = 
    valStack.len

  template setStackLen(s: int) = 
    # gh-10651
    if valStack.len == 0:
      assert s == 0
    else:
      valStack.setlen(s)

  template cleanUp = 
    discard


  # avoid dereference
  let constants = f.code.constants.addr
  let names = f.code.names.addr
  let fastLocals = f.fastLocals.addr
  let cellVars = f.cellVars.addr

  # in CPython this is a finite (20, CO_MAXBLOCKS) sized array as a member of 
  # frameobject. Safety is ensured by the compiler
  when not defined(js):
    var blockStack: seq[TryBlock]

  template hasTryBlock: bool = 
    0 < blockStack.len

  template getTryHandler: int = 
    blockStack[^1].handler
    

  template addTryBlock(opArg, stackPtr: int, cxt:PyExceptionObject=nil) = 
    blockStack.add(TryBlock(handler:opArg, sPtr:stackPtr, context:cxt))

  template getTopBlock: TryBlock = 
    blockStack[^1]

  template popTryBlock: int = 
    let ret = blockStack[^1].sPtr
    discard blockStack.pop
    ret

  template handleException(excp: PyObject) = 
    excpObj = excp
    break normalExecution

  template notDefined(name: string) =
    let msg = "name '" & name & "' is not defined" 
    handleException(newNameError newPyStr(msg))

  template genPop(T, toDel){.dirty.} =
    template pop(se: T, i: OpArg, unused: var PyObject): bool =
      if i < 0 or i > toDel.high: false
      else:
        toDel.del i
        true
  genPop (ptr seq[PyObject]), se[]  # fastLocals
  genPop (seq[PyStrObject]), se # localVars
  template deleteOrRaise(d, n; nMsg: string; elseDo) =
    var unused: PyObject
    if d.pop(n, unused):
      continue
    elseDo
    notDefined(nMsg)
  template deleteOrRaise(d, n; nMsg) =
    deleteOrRaise(d, n, nMsg): discard

  # the main interpreter loop
  try:
    # exception handler loop
    while true:
      var excpObj: PyObject
      # normal execution loop
      block normalExecution:
        # out of memory and keyboard interrupt handler
        try:
          while true:
            {. computedGoto .}
            let (opCode, opArg) = fetchInstr
            when defined(debug):
              echo fmt"{opCode}, {opArg}, {valStack.len}"
            case opCode
            of OpCode.PopTop:
              discard sPop

            of OpCode.DupTop:
              sPush sTop()

            of OpCode.NOP:
              continue

            of OpCode.UnaryPositive:
              doUnary(positive)

            of OpCode.UnaryNegative:
              doUnary(negative)

            of OpCode.UnaryNot:
              doUnary(Not)


            of OpCode.StoreSubscr:
              let idx = sPop()
              let obj = sPop()
              let value = sPop()
              discard obj.callMagic(setitem, idx, value, handleExcp=true)
            of OpCode.DeleteSubscr:
              let idx = sPop()
              let obj = sPop()
              discard obj.callMagic(delitem, idx, handleExcp=true)

            of OpCode.DeleteAttr:
              let name = names[opArg]
              let obj = sPop()
              discard obj.callMagic(delattr, name, handleExcp=true)

            of OpCode.BinarySubscr:
              doBinary(getitem)


            of OpCode.BinaryAdd:
              doBinary(add)

            of OpCode.BinarySubtract:
              doBinary(sub)

            of OpCode.BinaryPower:
              doBinary(pow)

            of OpCode.BinaryMultiply:
              doBinary(mul)

            of OpCode.BinaryModulo:
              doBinary(Mod)

            of OpCode.BinaryFloorDivide:
              doBinary(floorDiv)

            of OpCode.BinaryTrueDivide:
              doBinary(trueDiv)

            of OpCode.InplaceAdd:
              doInplace(add)

            of OpCode.InplaceSubtract:
              doInplace(sub)

            of OpCode.InplacePower:
              doInplace(pow)

            of OpCode.InplaceMultiply:
              doInplace(mul)

            of OpCode.InplaceModulo:
              doInplace(Mod)

            of OpCode.InplaceFloorDivide:
              doInplace(floorDiv)

            of OpCode.InplaceTrueDivide:
              doInplace(trueDiv)

            of OpCode.GetIter:
              let top = sTop()
              let (iterObj, _) = getIterableWithCheck(top)
              if iterObj.isThrownException:
                handleException(iterObj)
              sSetTop(iterObj)

            of OpCode.PrintExpr:
              let top = sPop()
              if top.id != pyNone.id:
                # all object should have a repr method properly initialized in typeobject.nim
                let reprObj = top.pyType.magicMethods.repr(top)
                if reprObj.isThrownException:
                  handleException(reprObj)

                # todo: optimization - build a cache
                let printFunction = PyNimFuncObject(bltinDict[newPyAscii"print"])
                let retObj = tpMagic(NimFunc, call)(printFunction, @[reprObj])
                if retObj.isThrownException:
                  handleException(retObj)

            of OpCode.LoadBuildClass:
              sPush bltinDict[newPyAscii"__build_class__"]
              
            of OpCode.ReturnValue:
              return sPop()

            of OpCode.PopBlock:
              if sEmpty:
                # no need to reset stack because it's already empty
                discard popTryBlock
              else:
                let top = sTop()
                setStackLen popTryBlock
                # previous `except` clause failed to handle the exception
                if top.isThrownException:
                  handleException(top)

            of OpCode.StoreName:
              unreachable("locals() scope not implemented")

            of OpCode.UnpackSequence:
              template incompatibleLengthError(gotLen: int) = 
                let got {. inject .} = $gotLen
                let msg = fmt"not enough values to unpack (expected {oparg}, got {got})"
                let excp = newValueError newPyStr(msg)
                handleException(excp)
              let s = sPop()
              if s.ofPyTupleObject():
                let t = PyTupleObject(s)
                if opArg != t.items.len:
                  incompatibleLengthError(t.items.len)
                for i in 1..opArg: 
                  sPush t.items[^i]
              elif s.ofPyListObject():
                let l = PyListObject(s)
                if opArg != l.items.len:
                  incompatibleLengthError(l.items.len)
                for i in 1..opArg: 
                  sPush l.items[^i]
              else:
                let (iterable, nextMethod) = getIterableWithCheck(s)
                if iterable.isThrownException:
                  handleException(iterable)
                # there is a much clever approach in CPython
                # because of the power of low level memory accessing
                var items = newseq[PyObject](opArg)
                for i in 0..<opArg:
                  let retObj = iterable.nextMethod
                  if retObj.isStopIter:
                    incompatibleLengthError(i)
                  elif retObj.isThrownException:
                    handleException(retObj)
                  else:
                    items[i] = retObj
                for i in 1..opArg: 
                  sPush items[^i]

            of OpCode.ForIter:
              let top = sTop()
              let nextFunc = top.getMagic(iternext)
              if nextFunc.isNil:
                echo top.pyType.name
                unreachable
              let retObj = nextFunc(top)
              if retObj.isStopIter:
                discard sPop()
                jumpTo(opArg)
              elif retObj.isThrownException:
                handleException(retObj)
              else:
                sPush retObj

            of OpCode.StoreAttr:
              let name = names[opArg]
              let owner = sPop()
              let v = sPop()
              discard owner.callMagic(setattr, name, v, handleExcp=true)

            of OpCode.StoreGlobal:
              let name = names[opArg]
              f.globals[name] = sPop()

            of OpCode.LoadConst:
              sPush(constants[opArg])

            of OpCode.LoadName:
              unreachable("locals() scope not implemented")

            of OpCode.BuildTuple:
              var args = newSeq[PyObject](opArg)
              for i in 1..opArg:
                args[^i] = sPop()
              let newTuple = newPyTuple(args)
              sPush newTuple

            of OpCode.BuildList:
              var args = newSeq[PyObject](opArg)
              for i in 1..opArg:
                args[^i] = sPop()
              # an optimization can save the copy
              let newList = newPyList(args)
              sPush newList 
            
            of OpCode.BuildSet:
              var args = initHashSet[PyObject](opArg)
              for i in 1..opArg:
                args.incl sPop()
              # an optimization can save the copy
              let newSet = newPySet(args)
              sPush newSet

            of OpCode.BuildMap:
              let d = newPyDict()
              for i in 0..<opArg:
                let key = sPop()
                let value = sPop()
                let retObj = tpMagic(Dict, setitem)(d, key, value)
                if retObj.isThrownException:
                  handleException(retObj)
              sPush d

            of OpCode.LoadAttr:
              let name = names[opArg]
              let obj = sTop()
              sSetTop obj.callMagic(getattr, name, handleExcp=true)

            of OpCode.CompareOp:
              let cmpOp = CmpOp(opArg)
              case cmpOp
              of CmpOp.Lt:
                doBinary(lt)
              of CmpOp.Le:
                doBinary(le)
              of CmpOp.Eq:
                doBinary(eq)
              of CmpOp.Ne:
                doBinary(ne)
              of CmpOp.Gt:
                doBinary(gt)
              of CmpOp.Ge:
                doBinary(ge)
              of CmpOp.In:
                sPush doBinaryContain
              of CmpOp.NotIn:
                let obj = doBinaryContain
                if obj.ofPyBoolObject:
                  sPush obj.callMagic(Not, handleExcp=true)
                else:
                  let boolObj = obj.callMagic(bool, handleExcp=true)
                  if not boolObj.ofPyBoolObject:
                    unreachable
                  sPush boolObj.callMagic(Not, handleExcp=true)
              of CmpOp.ExcpMatch:
                let targetExcp = sPop()
                if not targetExcp.isExceptionType:
                  let msg = "catching classes that do not inherit " & 
                            "from BaseException is not allowed"
                  handleException(newTypeError newPyAscii(msg))
                let currentExcp = PyExceptionObject(sTop())
                sPush matchExcp(PyTypeObject(targetExcp), currentExcp)
              else:
                unreachable  # should be blocked by ast, compiler

            of OpCode.ImportName:
              let name = names[opArg]
              let retObj = pyImport(name)
              if retObj.isThrownException:
                handleException(retObj)
              sPush retObj

            of OpCode.JumpIfFalseOrPop:
              let top = sTop()
              if getBoolFast(top) == false:
                jumpTo(opArg)
              else:
                discard sPop()

            of OpCode.JumpIfTrueOrPop:
              let top = sTop()
              if getBoolFast(top) == true:
                jumpTo(opArg)
              else:
                discard sPop()

            of OpCode.JumpForward, OpCode.JumpAbsolute:
              jumpTo(opArg)

            of OpCode.PopJumpIfFalse:
              let top = sPop()
              if getBoolFast(top) == false:
                jumpTo(opArg)

            of OpCode.PopJumpIfTrue:
              let top = sPop()
              if getBoolFast(top) == true:
                jumpTo(opArg)

            of OpCode.LoadGlobal:
              let name = names[opArg]
              var obj: PyObject
              if f.globals.hasKey(name):
                obj = f.globals[name]
              elif bltinDict.hasKey(name):
                obj = bltinDict[name]
              else:
                notDefined $name.str
              sPush obj

            of OpCode.SetupFinally:
              if hasTryBlock():
                addTryBlock(opArg, valStack.len, getTopBlock().context)
              else:
                addTryBlock(opArg, valStack.len, nil)

            of OpCode.LoadFast:
              let obj = fastLocals[opArg]
              if obj.isNil:
                let name = f.code.localVars[opArg]
                let msg = fmt"local variable {name} referenced before assignment"
                let excp = newUnboundLocalError(newPyStr msg)
                handleException(excp)
              sPush obj

            of OpCode.StoreFast:
              fastLocals[opArg] = sPop()

            of OpCode.DeleteGlobal:
              let name = names[opArg]
              deleteOrRaise f.globals, name, $name.str
            of OpCode.DeleteFast:
              deleteOrRaise fastLocals, opArg, $opArg:
                deleteOrRaise f.code.localVars, opArg, $opArg
            #of OpCode.DeleteDeref: deleteOrRaise cellVars, opArg #.refObj = sPop

            of OpCode.RaiseVarargs:
              case opArg
              of 0:
                if (not hasTryBlock) or getTopBlock.context.isNil:
                  let excp = newRunTimeError(newPyAscii"No active exception to reraise")
                  handleException(excp)
                else:
                  handleException(getTopBlock.context)
              of 1:
                let obj = sPop()
                var excp: PyObject
                if obj.isClass:
                  let newFunc = PyTypeObject(obj).magicMethods.New
                  if newFunc.isNil:
                    unreachable("__new__ of exceptions should be initialized")
                  excp = newFunc(@[])
                else:
                  excp = obj
                if not excp.ofPyExceptionObject:
                  unreachable
                PyExceptionObject(excp).thrown = true
                handleException(excp)
              else:
                unreachable(fmt"RaiseVarargs has opArg {opArg}")

            of OpCode.CallFunction:
              var args = newseq[PyObject](opArg)
              for i in 1..opArg:
                args[^i] = sPop()
              let funcObjNoCast = sPop()
              var retObj: PyObject
              # runtime function, evaluate recursively
              if funcObjNoCast.ofPyFunctionObject:
                let funcObj = PyFunctionObject(funcObjNoCast)
                # may fail because of wrong number of args, etc.
                let newF = newPyFrame(funcObj, args, f)
                if newF.isThrownException:
                  handleException(newF)
                retObj = PyFrameObject(newF).evalFrame
              # todo: should first dispatch Nim level function (same as CPython). 
              # this is of low priority because profit is unknown
              else:
                let callFunc = funcObjNoCast.pyType.magicMethods.call
                if callFunc.isNil:
                  let msg = fmt"{funcObjNoCast.pyType.name} is not callable"
                  retObj = newTypeError(newPyStr msg)
                else:
                  retObj = callFunc(funcObjNoCast, args)
              if retObj.isThrownException:
                handleException(retObj)
              sPush retObj

            of OpCode.MakeFunction:
              # other kinds not implemented
              assert opArg == 0 or opArg == 8
              let name = sPop()
              let code = sPop()
              var closure: PyObject
              if (opArg and 8) != 0:
                closure = sPop()
              sPush newPyFunc(PyStrObject(name), PyCodeObject(code), f.globals, closure)

            of OpCode.BuildSlice:
              var lower, upper, step: PyObject
              if opArg == 3:
                step = sPop()
              else:
                assert opArg == 2
                step = pyNone
              upper = sPop()
              lower = sTop()
              let slice = newPySlice(lower, upper, step)
              if slice.isThrownException:
                handleException(slice)
              sSetTop slice

            of OpCode.LoadClosure:
              sPush cellVars[opArg]

            of OpCode.LoadDeref:
              let c = cellVars[opArg]
              if c.refObj.isNil:
                let name = f.code.cellVars[opArg]
                let msg = fmt"local variable {name} referenced before assignment"
                let excp = newUnboundLocalError(newPyStr(msg))
                handleException(excp)
              sPush c.refObj

            of OpCode.StoreDeref:
              cellVars[opArg].refObj = sPop

            of OpCode.ListAppend:
              let top = sPop()
              let l = sPeek(opArg)
              assert l.ofPyListObject
              PyListObject(l).items.add top

            else:
              let msg = fmt"!!! NOT IMPLEMENTED OPCODE {opCode} IN EVAL FRAME !!!"
              return newNotImplementedError(newPyAscii msg) # no need to handle
        except OutOfMemDefect:
          excpObj = newMemoryError(newPyAscii"Out of Memory")
          handleException(excpObj)
        except InterruptError:
          excpObj = newKeyboardInterruptError(newPyAscii"Keyboard Interrupt")
          handleException(excpObj)

      # exception handler, return exception or re-enter the loop with new instruction index
      block exceptionHandler:
        assert (not excpObj.isNil)
        assert excpObj.ofPyExceptionObject
        let excp = PyExceptionObject(excpObj)
        excp.setTraceBack
        while hasTryBlock():
          let topBlock = getTopBlock()
          case topBlock.status
          of TryStatus.Try: # error occured in `try` suite
            excp.context = topBlock.context
            topBlock.context = excp
            topBlock.status = TryStatus.Except
            setStackLen topBlock.sPtr
            sPush excp # for comparison in `except` clause
            jumpTo(topBlock.handler)
            when defined(debug):
              echo fmt"handling exception, jump to {topBlock.handler}"
            break exceptionHandler # continue normal execution
          of TryStatus.Except: # error occured in `except` suite
            if excp.context.isNil: # raised without nesting try/except
              excp.context = topBlock.context 
            # else with nesting try/except, the context has already been set properly
            setStackLen popTryBlock() # try to find a handler along the stack
          else:
            unreachable
        return excp
  finally:
    cleanUp()


when defined(js):
  proc pyImport*(name: PyStrObject): PyObject =
    newRunTimeError(newPyAscii"Can't import in js mode")
else:
  import os
  proc pyImport*(name: PyStrObject): PyObject =
    let filepath = pyConfig.path.joinPath($name.str).addFileExt("py")
    if not filepath.fileExists:
      let msg = fmt"File {filepath} not found"
      return newImportError(newPyStr(msg))
    let input = readFile(filepath)
    let compileRes = compile(input, filepath)
    if compileRes.isThrownException:
      return compileRes

    let co = PyCodeObject(compileRes)

    when defined(debug):
      echo co
    let fun = newPyFunc(name, co, newPyDict())
    let f = newPyFrame(fun)
    let retObj = f.evalFrame
    if retObj.isThrownException:
      return retObj
    let module = newPyModule(name)
    module.dict = f.globals
    module

proc newPyFrame*(fun: PyFunctionObject): PyFrameObject = 
  let obj = newPyFrame(fun, @[], nil)
  if obj.isThrownException:
    unreachable
  else:
    return PyFrameObject(obj)

proc newPyFrame*(fun: PyFunctionObject, 
                 args: seq[PyObject], 
                 back: PyFrameObject): PyObject = 
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


# interfaces to upper level
proc runCode*(co: PyCodeObject): PyObject = 
  when defined(debug):
    echo co
  let fun = newPyFunc(newPyAscii("<module>"), co, newPyDict())
  let f = newPyFrame(fun)
  f.evalFrame


proc runString*(input, fileName: string): PyObject = 
  let compileRes = compile(input, fileName)
  if compileRes.isThrownException:
    return compileRes
  runCode(PyCodeObject(compileRes))

template orPrintTb(retRes): bool{.dirty.} =
  if retRes.isThrownException:
    PyExceptionObject(retRes).printTb
    false
  else:
    true

proc runSimpleString*(input, fileName: string): bool =
  ## returns if successful.
  ##
  ## a little like `_PyRun_SimpleStringFlagsWithName`
  ## but as you may know, it only returns -1 for failure and
  ## 0 for success, so returing a bool is better
  let compileRes = compile(input, fileName)
  result = compileRes.orPrintTb
  if not result: return
  let runRes = runCode(PyCodeObject(compileRes))
  result = runRes.orPrintTb
