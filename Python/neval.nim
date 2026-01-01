
import strformat
import tables
import std/sets
import compile
import opcode
import builtindict
import ./[call, traceback]
import ../Include/internal/pycore_global_strings
import ../Objects/typeobject/apis/attrs
import ../Objects/[pyobject, baseBundle, tupleobject, listobject, dictobject,
                   sliceobject, codeobject, frameobject, funcobject, cellobject,
                   setobject, notimplementedobject, boolobjectImpl,
                   exceptionsImpl,
                   ]
import ../Objects/abstract/[dunder, number,]
import ../Utils/utils
import ./[
  neval_frame,
  pyimport,
  intrinsics,
]
export pyimport, neval_frame

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
    moreToPush: range[0..2]  ## SETUP_FINALLY/CLEANUP/WITH -> 0,1,2
    withExitFunc: PyObject  ## only for WITH_EXCEPT_START

{.push raises: [].}
# forward declarations
proc evalFrame*(f: PyFrameObject): PyObject
{.pop.}

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

template doBinaryAttrImpl(opName): PyObject =
  let op2 = sPop()
  let op1 = sTop()
  op1.callMagic(opName, op2, handleExcp=true)

template doBinaryAttr(opName) =
  let res = doBinaryAttrImpl(opName)
  sSetTop res

template doBinaryImpl(opName): PyObject =
  let op2 = sPop()
  let op1 = sTop()
  let res =
    when declared(`PyNumber opName`): `PyNumber opName`(op1, op2)
    else: `PyObject opName`(op1, op2)
  if res.isThrownException:
    handleException(res)
  res

template doBinaryContain: PyObject = 
  ## the same as doBinary, but the order of op1, op2 is reversed!
  let op1 = sPop()
  let op2 = sTop()
  op1.callMagic(contains, op2, handleExcp=true)
template doBinary(opName: untyped) =
  let res = doBinaryImpl(opName)
  sSetTop res

template getBoolFast(obj: PyObject): bool = 
  ## called "fast" only due to historical reason
  var b: bool
  let exc = PyObject_IsTrue(obj, b)
  if not exc.isNil:
    handleException(exc)
  b


template evalBuildMapTo(d) =
  let d = newPyDict()
  for i in 0..<opArg:
    let key = sPop()
    let value = sPop()
    let retObj = tpMagic(Dict, setitem)(d, key, value)
    if retObj.isThrownException:
      handleException(retObj)

proc evalFrame*(f: PyFrameObject): PyObject = 
  # instructions are fetched so frequently that we should build a local cache
  # instead of doing tons of dereference
  var rt = newEvaluator(evalFrame)
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
   
  # valStack, blockStack were once declared as global variable in JS,
  #   as js target would fail in the past. ref nim-lang/Nim#10651

  # in future, should get rid of the abstraction of seq and use a dynamically
  # created buffer directly. This can reduce time cost of the core neval function
  # by 25%
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
  var blockStack: seq[TryBlock]

  template hasTryBlock: bool = 
    0 < blockStack.len


  template addTryBlock(opArg, stackPtr: int, cxt:PyExceptionObject=nil, moreToPushThan1=0, twithExitFunc: PyObject = nil) = 
    blockStack.add(TryBlock(handler:opArg, sPtr:stackPtr, context:cxt, moreToPush: moreToPushThan1, withExitFunc: twithExitFunc))

  template getTopBlock: TryBlock = 
    blockStack[^1]

  template popTryBlock: int = 
    let ret = blockStack[^1].sPtr
    discard blockStack.pop
    ret

  template handleException(excp: PyObject) = 
    excpObj = excp
    break normalExecution

  template notDefined(nam: PyStrObject) =
    let msg = newPyAscii"name '" & nam & newPyAscii"' is not defined" 
    let nameErr = newNameError msg
    nameErr.name = nam
    handleException(nameErr)

  template genPop(T, toDel){.dirty.} =
    template pop(se: T, i: OpArg, unused: var PyObject): bool =
      if i < 0 or i > toDel.high: false
      else:
        toDel.del i
        true
  genPop (ptr seq[PyObject]), se[]  # fastLocals
  genPop (seq[PyStrObject]), se # localVars
  template deleteOrRaise(d, n; nMsg: PyStrObject; elseDo) =
    var unused: PyObject
    if d.pop(n, unused):
      continue
    {.push warning[UnreachableCode]: off.}
    # XXX: if `elseDo` is still `deleteOrRaise`, then notDefined's handleException
    #   will occur twice, so the latter is `UnreachableCode`
    elseDo
    {.pop.}
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
        template handleSetup(n; exitFunc: untyped = nil) =
          addTryBlock(opArg, valStack.len,
            if hasTryBlock(): getTopBlock().context
            else: nil
            ,
          n, exitFunc)

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

            of OpCode.UnaryInvert:
              doUnary(invert)


            of OpCode.StoreSubscr:
              let idx = sPop()
              let obj = sPop()
              let value = sPop()
              let res = PyObject_SetItem(obj, idx, value)
              if res.isThrownException:
                handleException res
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

            of OpCode.BinaryAnd:   doBinary(And)
            of OpCode.BinaryOr:    doBinary(Or)
            of OpCode.BinaryXor:   doBinary(Xor)
            of OpCode.BinaryLshift:doBinary(lshift)
            of OpCode.BinaryRshift:doBinary(rshift)

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

            of OpCode.InplaceAnd:
              doInplace(And)
            of OpCode.InplaceOr:
              doInplace(Or)
            of OpCode.InplaceXor:
              doInplace(Xor)
            of OpCode.InplaceLshift:
              doInplace(lshift)
            of OpCode.InplaceRshift:
              doInplace(rshift)

            of OpCode.GetIter:
              let top = sTop()
              let (iterObj, _) = getIterableWithCheck(top)
              if iterObj.isThrownException:
                handleException(iterObj)
              sSetTop(iterObj)

            of OpCode.PrintExpr:
              let top = sPop()
              var unused: PyObject
              let retObj: PyBaseErrorObject = print_expr(top, unused)
              if not retObj.isNil:
                handleException(retObj)

            of OpCode.LoadBuildClass:
              sPush KeyError!bltinDict[newPyAscii"__build_class__"]
              
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

            of OpCode.PopExcept:
              # remove the exception object left on stack and pop the try-block
              excpObj = sPop()

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
              for i in countdown(opArg-1, 0):
                args[i] = sPop()
              let newTuple = newPyTuple(args)
              sPush newTuple

            of OpCode.BuildList:
              var args = newSeq[PyObject](opArg)
              for i in countdown(opArg-1, 0):
                args[i] = sPop()
              # an optimization can save the copy
              let newList = newPyList(args)
              sPush newList 
            
            of OpCode.BuildSet:
              var args: HashSet[PyObject]
              handleHashExc handleException:
                args = initHashSet[PyObject](opArg)
              handleHashExc handleException:
                for _ in 1..opArg:
                  args.incl sPop()
              # an optimization can save the copy
              let newSet = newPySet(args)
              sPush newSet

            of OpCode.BuildMap:
              evalBuildMapTo(d)
              sPush d

            of OpCode.LoadAttr:
              let name = names[opArg]
              let obj = sTop()
              sSetTop obj.callMagic(getattr, name, handleExcp=true)

            of OpCode.CompareOp:
              let cmpOp = CmpOp(opArg)
              case cmpOp
              of CmpOp.Lt:
                doBinaryAttr(lt)
              of CmpOp.Le:
                doBinaryAttr(le)
              of CmpOp.Eq:
                doBinaryAttr(eq)
              of CmpOp.Ne:
                doBinaryAttr(ne)
              of CmpOp.Gt:
                doBinaryAttr(gt)
              of CmpOp.Ge:
                doBinaryAttr(ge)
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
              of CmpOp.Is:
                let op2 = sPop()
                let op1 = sTop()
                sSetTop newPyBool Py_IS(op1, op2)
              of CmpOp.IsNot:
                let op2 = sPop()
                let op1 = sTop()
                sSetTop newPyBool(not Py_IS(op1, op2))
              of CmpOp.ExcpMatch:
                let targetExcp = sPop()
                if not targetExcp.isExceptionType:
                  let msg = "catching classes that do not inherit " & 
                            "from BaseException is not allowed"
                  handleException(newTypeError newPyAscii(msg))
                let currentExcp = PyExceptionObject(sTop())
                sPush matchExcp(PyTypeObject(targetExcp), currentExcp)

            of OpCode.ImportName:
              let name = names[opArg]
              let retObj = rt.pyImport(name)
              if retObj.isThrownException:
                handleException(retObj)
              sPush retObj
            of OpCode.ImportFrom:
              let module = sTop()
              let name = names[opArg]
              let retObj = module.callMagic(getattr, name, handleExcp=true)
              if retObj.isThrownException:
                handleException(retObj)
              # TODO:_PyEval_ImportFrom
              #  after sys.module impl
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
              f.globals.withValue(name, value):
                obj = value[]
              do:
                bltinDict.withValue(name, value):
                  obj = value[]
                do:
                  notDefined name
              sPush obj
            #TODO:dis SetupFinally, SetupCleanup, SetupWith shall be pesudo opcodes,
            #  not real opcodes,
            #  (being replaced during `assemble`)
            of OpCode.SetupFinally: handleSetup(0)
            of OpCode.SetupCleanup: handleSetup(1)
            of OpCode.SetupWith:
              var exit: PyObject
              block BeforeWith:
                let context_manager = sPop()

                let error_string = proc (): string =
                  fmt"'{context_manager.typeName:.200}' object does not support the context manager protocol"

                # lookup __enter__ and call it immediately; raise TypeError if missing
                var enter_meth = PyObject_LookupSpecial(context_manager, pyDUId enter)
                if enter_meth.isNil:
                  let exc = newTypeError newPyStr(error_string())
                  handleException(exc)

                # lookup __exit__; missing __exit__ is an immediate TypeError
                exit = PyObject_LookupSpecial(context_manager, pyDUId exit)
                if exit.isNil:
                  let exc = newTypeError newPyStr(error_string() & " (missed __exit__ method)")
                  handleException(exc)

                # call the __enter__ method
                var enter_res = enter_meth.call
                if enter_res.isThrownException:
                  handleException(enter_res)

                sPush exit
                sPush enter_res

              handleSetup(2, exit)

            of OpCode.WithExceptStart:
              let
                lastiOfExc = sPop()
                val = sPop()
                unused = sPop()  # enter_res (keep)
                exit = sPop()
              discard unused
              assert lastiOfExc.ofPyIntObject
              let tb = PyExceptionObject(val).traceback
              let exitRet = exit.fastCall(@[val.pyType, val, tb])
              if exitRet.isThrownException:
                handleException(exitRet)
              # restore stack: push exit, enter_res, then insert exitRet, exc, lasti
              sPush exit
              sPush unused
              sPush lastiOfExc
              sPush val
              sPush exitRet

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
              deleteOrRaise f.globals, name, name
            of OpCode.DeleteFast:
              let name = names[opArg]
              deleteOrRaise fastLocals, opArg, name:
                deleteOrRaise f.code.localVars, opArg, name
            #of OpCode.DeleteDeref: deleteOrRaise cellVars, opArg #.refObj = sPop

            of OpCode.Reraise:
              let exc = sPop()
              assert opArg in 0..2
              if opArg != 0:
                #XXX:CPython allows opArg==2 but does nothing other than doing what's done when opArg==1
                lastI = sPop().PyIntObject.toSomeSignedIntUnsafe[:int]()
              handleException(exc)
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
                  excp = newFunc(@[], nil)
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

              # todo: should first dispatch Nim level function (same as CPython). 
              # this is of low priority because profit is unknown
              let callFunc = funcObjNoCast.pyType.magicMethods.call
              if callFunc.isNil:
                let msg = fmt"{funcObjNoCast.pyType.name} is not callable"
                retObj = newTypeError(newPyStr msg)
              else:
                retObj = callFunc(funcObjNoCast, args, nil)
              if retObj.isThrownException:
                handleException(retObj)
              sPush retObj
            of OpCode.CallFunction_EX:
              # cpython/Python/bytecodes.c
              var args = newseq[PyObject](opArg)
              for i in 1..opArg:
                args[^i] = sPop()
              let funcObjNoCast = sPop()

              let kw = PyDictObject sPop()

              var retObj: PyObject
              # runtime function, evaluate recursively
              if funcObjNoCast.ofPyFunctionObject:
                let msg = "call python non-builtin function with keyword is not implemented yet"
                return newNotImplementedError(newPyAscii msg) # no need to handle

                #[
                let funcObj = PyFunctionObject(funcObjNoCast)
                # may fail because of wrong number of args, etc.
                let newF = newPyFrame(funcObj, args, f)
                if newF.isThrownException:
                  handleException(newF)
                retObj = PyFrameObject(newF).evalFrame
              # todo: should first dispatch Nim level function (same as CPython). 
              # this is of low priority because profit is unknown
                ]#
              else:
                let callFunc = funcObjNoCast.pyType.magicMethods.call
                if callFunc.isNil:
                  let msg = fmt"{funcObjNoCast.pyType.name} is not callable"
                  retObj = newTypeError(newPyStr msg)
                else:
                  retObj = callFunc(funcObjNoCast, args, kw)
              if retObj.isThrownException:
                handleException(retObj)
              sPush retObj

            of OpCode.MakeFunction:
              # support defaults, kw-defaults, vararg and closure flags
              # opArg bit 0x1 : positional defaults tuple present
              # opArg bit 0x2 : kw-only defaults dict present
              # opArg bit 0x8 : closure tuple present
              # opArg bit 0x10: vararg name constant present
              let name = sPop()
              let code = sPop()
              var varargName: PyObject = nil
              var defaults: PyObject = nil
              var kwDefaults: PyObject = nil
              var closure: PyObject = nil
              if (opArg and 16) != 0:
                varargName = sPop()
              if (opArg and 1) != 0:
                defaults = sPop()
              if (opArg and 2) != 0:
                kwDefaults = sPop()
              if (opArg and 8) != 0:
                closure = sPop()
              let funObj = newPyFunc(PyStrObject(name), PyCodeObject(code), f.globals, PyTupleObject(closure), PyTupleObject(defaults))
              if not varargName.isNil:
                funObj.code.varArgName = PyStrObject(varargName)
              # attach kwDefaults to code object for call-time handling
              if not kwDefaults.isNil:
                # kwDefaults is a tuple of values corresponding to code.kwOnlyNames
                let kwt = PyTupleObject(kwDefaults)
                PyCodeObject(code).kwOnlyDefaults = kwt.items
                # build kwdefaults dict on function
                let kwd = newPyDict()
                for i, name in PyCodeObject(code).kwOnlyNames:
                  if i < kwt.items.len:
                    kwd[name] = kwt.items[i]
                funObj.kwdefaults = kwd
              sPush funObj

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

            of ListAppend:
              let top = sPop()
              let l = sPeek(opArg)
              assert l.ofPyListObject
              PyListObject(l).add top
            
            of SetAdd:
              let top = sPop()
              let s = sPeek(opArg)
              assert s.ofPySetObject
              handleHashExc handleException:
                PySetObject(s).items.incl top
            
            of MapAdd:
              let value = sPop()
              let key = sPop()
              let d = sPeek(opArg)
              assert d.ofPyDictObject
              let retObj = tpMagic(Dict, setitem)(PyDictObject(d), key, value)
              if retObj.isThrownException:
                handleException(retObj)

            else:
              let msg = fmt"!!! NOT IMPLEMENTED OPCODE {opCode} IN EVAL FRAME !!!"
              return newNotImplementedError(newPyAscii msg) # no need to handle
        except OutOfMemDefect:
          excpObj = newMemoryError(newPyAscii"Out of Memory")
          handleException(excpObj)
        except InterruptError:
          excpObj = newKeyboardInterrupt(newPyAscii"Keyboard Interrupt")
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
            case topBlock.moreToPush
            of 0: discard
            of 1: sPush newPyInt lastI
            of 2:
              sPeek(3  # one for excp, one for unused
                ) = topBlock.withExitFunc # resume exit func
              sPush newPyInt lastI
            jumpTo(topBlock.handler)
            when defined(debug_instr_except):
              echo fmt"  --- handling exception, jump to {topBlock.handler}"
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


# interfaces to upper level
proc runCode*(co: PyCodeObject, globals = newPyDict()): PyObject = 
  when defined(debug):
    echo co
  let fun = newPyFunc(co.codeName, co, globals)
  let f = newPyFrame(fun)
  f.evalFrame

proc evalCode*(co: PyCodeObject; globals = newPyDict(), locals: PyDictObject = nil): PyObject =
  ## PyEval_EvalCode
  if not locals.isNil:
    assert system.`==`(globals, locals), "Currently, locals must be literal equal to globals"
  co.runCode globals
