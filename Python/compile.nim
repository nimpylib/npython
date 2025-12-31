import algorithm


import macros

import tables
import ./coreconfig
import ast
import asdl
import symtable
import opcode
import ../Parser/parser
import ../Objects/[
  pyobject, stringobjectImpl, exceptionsImpl,
  setobject,
  codeobject, noneobject]
import ../Objects/stringobject/strformat
import ../Utils/utils
import ../Include/cpython/compile as compile_h
export compile_h
type
  Instr = ref object of RootObj
    opCode*: OpCode
    lineNo: int

  ArgInstr = ref object of Instr
    opArg: int

  JumpInstr = ref object of ArgInstr
    target: BasicBlock


  BlockType {. pure .} = enum
    Misc,
    While,
    For


  # node in CFG, an abstraction layer for convenient byte code offset computation
  BasicBlock = ref object
    instrSeq: seq[Instr]
    tp: BlockType
    next: BasicBlock
    seenReturn: bool
    offset: int

  # for each function, lambda, class, etc
  CompilerUnit = ref object
    ste: SymTableEntry
    blocks: seq[BasicBlock]
    # should use a dict, but we don't have hash and bunch of 
    # other things
    constants: seq[PyObject]
    codeName: PyStrObject

  Compiler = ref object
    units: seq[CompilerUnit]
    st: SymTable
    interactive: bool
    fileName: PyStrObject
    flags: PyCompilerFlags
    optimize: int
#TODO:compile flags current no use
proc `$`*(i: Instr): string =
  $i.opCode

proc newInstr(opCode: OpCode, lineNo: int): Instr =
  assert(not (opCode in hasArgSet))
  result = new Instr
  result.opCode = opCode
  result.lineNo = lineNo

proc newArgInstr(opCode: OpCode, opArg, lineNo: int): ArgInstr =
  assert opCode in hasArgSet
  result = new ArgInstr
  result.opCode = opCode
  result.opArg = opArg
  result.lineNo = lineNo

proc newJumpInstr(opCode: OpCode, target: BasicBlock, lineNo: int): JumpInstr =
  assert opCode in jumpSet
  result = new JumpInstr
  result.opCode = opCode
  result.opArg = -1           # dummy, set during assemble
  result.target = target
  result.lineNo = lineNo

proc newBasicBlock(tp=BlockType.Misc): BasicBlock =
  result = new BasicBlock
  result.seenReturn = false
  result.tp = tp

proc newCompilerUnit(st: SymTable, 
                     node: AstNodeBase, 
                     codeName: PyStrObject): CompilerUnit =
  result = new CompilerUnit
  result.ste = st.getSte(node)
  result.blocks.add(newBasicBlock())
  result.codeName = codeName


proc newCompiler(root: AsdlModl, fileName: PyStrObject, flags: PyCompilerFlags, optimize: int): Compiler{.raises: [SyntaxError].} =
  result = new Compiler
  result.st = newSymTable(root)
  result.units.add(newCompilerUnit(result.st, root, newPyAscii"<module>"))
  result.fileName = fileName
  result.flags = flags
  result.optimize = if optimize == -1: Py_GetConfig().optimization_level else: optimize


method toTuple(instr: Instr): (OpCode, OpArg, int) {.base, raises: [].} =
  (instr.opCode, -1, instr.lineNo)


method toTuple(instr: ArgInstr): (OpCode, OpArg, int){.raises:[].} =
  (instr.opCode, instr.opArg, instr.lineNo)

{. push inline, cdecl .}

proc constantId(cu: CompilerUnit, pyObject: PyObject): int =
  result = cu.constants.find(pyObject)
  if result != -1:
    return
  result = cu.constants.len
  cu.constants.add(pyObject)


# the top compiler unit
proc tcu(c: Compiler): CompilerUnit =
  c.units[^1]


# the top symbal table entry
proc tste(c: Compiler): SymTableEntry =
  c.tcu.ste


# the top code block
proc tcb(cu: CompilerUnit): BasicBlock =
  cu.blocks[^1]

proc tcb(c: Compiler): BasicBlock =
  c.tcu.tcb

proc len(cb: BasicBlock): int =
  cb.instrSeq.len

# last line number
proc lastLineNo(cu: CompilerUnit): int = 
  for i in 1..cu.blocks.len:
    case cu.blocks[^i].len
    of 0:
      continue
    else:
      return cu.blocks[^i].instrSeq[^1].lineNo

proc lastLineNo(c: Compiler): int = 
  c.tcu.lastLineNo

proc numCodes(cu: CompilerUnit): int =
  for b in cu.blocks:
    result += b.len

proc addOp(cu: CompilerUnit, instr: Instr) =
  cu.blocks[^1].instrSeq.add(instr)


proc addOp(c: Compiler, instr: Instr) =
  c.tcu.addOp(instr)


proc addOp(c: Compiler, opCode: OpCode, lineNo: int) =
  assert (not (opCode in hasArgSet))
  c.tcu.addOp(newInstr(opCode, lineNo))


proc addBlock(c: Compiler, cb: BasicBlock) =
  c.tcu.blocks.add(cb)

proc addLoadConst(cu: CompilerUnit, pyObject: PyObject, lineNo: int) =
  let arg = cu.constantId(pyObject)
  let instr = newArgInstr(OpCode.LoadConst, arg, lineNo)
  cu.addOp(instr)

proc addLoadConst(c: Compiler, pyObject: PyObject, lineNo: int) = 
  c.tcu.addLoadConst(pyObject, lineNo)

{. pop .}

template genScopeCase(X){.dirty.} =
 proc `add X Op`(c: Compiler, nameStr: PyStrObject, lineNo: int){.raises:[].} = 
  template `!`(e): untyped = KeyError!e
  let scope = !c.tste.getScope(nameStr)

  var
    opArg: int
    opCode: OpCode

  case scope
  of Scope.Local:
    opArg = !c.tste.localId(nameStr)
    opCode = OpCode.`X Fast`
  of Scope.Global:
    opArg = c.tste.nameId(nameStr)
    opCode = OpCode.`X Global`
  of Scope.Cell:
    opArg = !c.tste.cellId(nameStr)
    opCode = OpCode.`X Deref`
  of Scope.Free:
    opArg = !c.tste.freeId(nameStr)
    opCode = OpCode.`X Deref`

  let instr = newArgInstr(opCode, opArg, lineNo)
  c.addOp(instr)

 proc `add X Op`(c: Compiler, name: AsdlIdentifier, lineNo: int) =
  let nameStr = name.value
  `add X Op`(c, nameStr, lineNo)


genScopeCase Load
genScopeCase Store
genScopeCase Delete


proc assemble(cu: CompilerUnit, fileName: PyStrObject): PyCodeObject =
  # compute offset of opcodes
  for i in 0..<cu.blocks.len-1:
    let last_block = cu.blocks[i]
    let this_block = cu.blocks[i+1]
    this_block.offset = last_block.offset + last_block.len
  # setup jump instruction destination
  for cb in cu.blocks:
    for instr in cb.instrSeq:
      if instr of JumpInstr:
        let jumpInstr = JumpInstr(instr)
        jumpInstr.opArg = jumpInstr.target.offset
  # add return if not seen
  if not cu.tcb.seenReturn:
    # an empty code object without last line number does not exist
    cu.addLoadConst(pyNone, cu.lastLineNo)
    cu.addOp(newInstr(OpCode.ReturnValue, cu.lastLineNo))
  # convert compiler unit to code object
  result = newPyCode(cu.codeName, fileName, cu.numCodes)
  for cb in cu.blocks:
    for instr in cb.instrSeq:
      result.addOpCode(instr.toTuple())
  result.constants = cu.constants
  result.names = cu.ste.namesToSeq()
  result.localVars = cu.ste.localVarsToSeq()
  # todo: add flags for faster simple function call
  result.cellVars = cu.ste.cellVarsToSeq()
  result.freeVars = cu.ste.freeVarsToSeq()
  result.argNames = newSeq[PyStrObject](cu.ste.argVars.len)
  result.argScopes = newSeq[(Scope, int)](cu.ste.argVars.len)
  for argName, argIdx in cu.ste.argVars.pairs:
    let scope = KeyError!cu.ste.getScope(argName)
    var scopeIdx: int
    case scope
    of Scope.Local:
      scopeIdx = KeyError!cu.ste.localId(argName)
    of Scope.Global:
      scopeIdx = cu.ste.nameId(argName)
    of Scope.Cell:
      scopeIdx = KeyError!cu.ste.cellId(argName)
    of Scope.Free:
      unreachable("arguments can't be free")
    result.argNames[argIdx] = argName
    result.argScopes[argIdx] = (scope, scopeIdx)
  # propagate vararg and kw-only info from symtable
  result.varArgName = cu.ste.varArg
  result.kwOnlyNames = cu.ste.kwOnlyArgs
  result.kwOnlyDefaults = cu.ste.kwOnlyDefaults


proc makeFunction(c: Compiler, cu: CompilerUnit, 
                  functionName: PyStrObject, lineNo: int, extraFlags: int = 0) = 
  assert (not cu.codeName.isNil)
  # take the compiler unit and make it a function on stack top
  let co = cu.assemble(c.fileName)

  var flag: int
  # stack and flag according to CPython document:
  # 0x01 a tuple of default values for positional-only and positional-or-keyword parameters in positional order
  # 0x02 a dictionary of keyword-only parameters’ default values
  # 0x04 an annotation dictionary
  # 0x08 a tuple containing cells for free variables, making a closure
  # the code associated with the function (at TOS1)
  # the qualified name of the function (at TOS)
  
  if co.freeVars.len != 0:
    # several sources of the cellVars and freeVars:
    # * a closure in the body used it
    # * the code it self is a closure
    # In the first case, the variable may be declared in the code or in the upper level
    # In the second case, the variable must be declared in the upper level
    for name in co.freeVars:
      if c.tste.hasCell(name):
        c.addOp(newArgInstr(OpCode.LoadClosure, KeyError!c.tste.cellId(name), lineNo))
      elif c.tste.hasFree(name):
        c.addOp(newArgInstr(OpCode.LoadClosure, KeyError!c.tste.freeId(name), lineNo))
      else:
        unreachable
    c.addOp(newArgInstr(OpCode.BuildTuple, co.freeVars.len, lineNo))
    flag = flag or 8

  # incorporate extra flags (e.g., defaults presence)
  flag = flag or extraFlags

  # if vararg name exists, load it so MakeFunction can attach it to function object
  if not cu.ste.varArg.isNil:
    c.tcu.addLoadConst(cu.ste.varArg, lineNo)
    flag = flag or 16
    when defined(debug):
      echo "DEBUG: compile.makeFunction found vararg " & $cu.ste.varArg
  c.tcu.addLoadConst(co, lineNo)
  c.tcu.addLoadConst(functionName, lineNo)
  # currently flag may be 0 or 8 or include extraFlags
  c.addOp(newArgInstr(OpCode.MakeFunction, flag, lineNo))

macro genMapMethod(methodName, code: untyped): untyped =
  result = newStmtList()
  for child in code[0]:
    let astIdent = child[0]
    let opCodeIdent = child[1]
    let newMapMethod = nnkMethodDef.newTree(
      methodName,
      newEmptyNode(),
      newEmptyNode(),
      nnkFormalParams.newTree(
        ident("OpCode"),
        newIdentDefs(ident("astNode"), ident("Ast" & $astIdent))
      ),
      pragmaRaiseNode(methodName),
      newEmptyNode(),
      nnkStmtList.newTree(
        nnkDotExpr.newTree(
          ident("OpCode"),
          opCodeIdent
        )
      )
    )
    result.add(newMapMethod)

method toOpCode(op: AsdlOperator): OpCode {.base, raises: [].} =
  echo op
  assert false


genMapMethod toOpCode:
  {
    Add: BinaryAdd,
    Sub: BinarySubtract,
    Mult: BinaryMultiply,
    Div: BinaryTrueDivide,
    Mod: BinaryModulo,
    Pow: BinaryPower,
    FloorDiv: BinaryFloorDivide,
    
    BitAnd: BinaryAnd,
    BitOr:  BinaryOr,
    BitXor: BinaryXor,
    Lshift: BinaryLshift,
    Rshift: BinaryRshift,

  }

method toInplaceOpCode(op: AsdlOperator): OpCode {.base, raises: [].} =
  echo "inplace ",op
  assert false
genMapMethod toInplaceOpCode:
  {
    Add: InplaceAdd,
    Sub: InplaceSubtract,
    Mult: InplaceMultiply,
    Div: InplaceTrueDivide,
    Mod: InplaceModulo,
    Pow: InplacePower,
    FloorDiv: InplaceFloorDivide,

    BitAnd: InplaceAnd,
    BitOr:  InplaceOr,
    BitXor: InplaceXor,
    Lshift: InplaceLshift,
    Rshift: InplaceRshift,
  }


method toOpCode(op: AsdlUnaryop): OpCode {.base, raises: [].} =
  unreachable

#  unaryop = (Invert, Not, UAdd, USub)
genMapMethod toOpCode:
  {
    Invert: UnaryInvert,
    Not: UnaryNot,
    UAdd: UnaryPositive,
    USub: UnaryNegative,
  }



macro compileMethod(astNodeName, funcDef: untyped): untyped =
  result = nnkMethodDef.newTree(
    ident("compile"),
    newEmptyNode(),
    newEmptyNode(),
    nnkFormalParams.newTree(
      newEmptyNode(),
      newIdentDefs(
        ident("astNode"),
        ident("Ast" & $astNodeName)
      ),
      newIdentDefs(
        ident("c"),
        ident("Compiler")
      ),
    ),
    pragmaRaiseSyntaxErrorNode(astNodeName),
    newEmptyNode(),
    funcdef,
  )


template compileSeq(c: Compiler, s: untyped) =
  for astNode in s:
    c.compile(astNode)

# todo: too many dispachers here! used astNode token to dispatch (if have spare time...)
method compile(astNode: AstNodeBase, c: Compiler) {.base, raises: [SyntaxError].} =
  echo "!!!WARNING, ast node compile method not implemented"
  echo astNode
  echo "###WARNING, ast node compile method not implemented"
  # let it compile, the result shown is better for debugging

template compile*(c: Compiler, astNode: AstNodeBase) =
  bind compile
  compile(astNode, c)

compileMethod Module:
  c.compileSeq(astNode.body)


compileMethod Interactive:
  c.interactive = true
  c.compileSeq(astNode.body)


compileMethod FunctionDef:
  for deco in astNode.decorator_list:
    c.compile(deco)
  assert astNode.returns == nil
  # compile kw-only defaults first, then positional defaults; both evaluated in defining scope before MakeFunction
  let argsNode = AstArguments(AstFunctionDef(astNode).args)
  var extraFlags = 0
  # maybe allows disable complex function def
  when compiles(argsNode.kw_defaults):
    if argsNode.kw_defaults.len > 0:
      for defExpr in argsNode.kw_defaults:
        c.compile(defExpr)
      c.addOp(newArgInstr(OpCode.BuildTuple, argsNode.kw_defaults.len, astNode.lineNo.value))
      extraFlags = extraFlags or 2
  when compiles(argsNode.defaults):
    if argsNode.defaults.len > 0:
      for defExpr in argsNode.defaults:
        c.compile(defExpr)
      c.addOp(newArgInstr(OpCode.BuildTuple, argsNode.defaults.len, astNode.lineNo.value))
      extraFlags = extraFlags or 1
  # create inner compiler unit so function body compiles into it
  c.units.add(newCompilerUnit(c.st, astNode, astNode.name.value))
  assert (not c.tcu.codeName.isNil)
  c.compileSeq(astNode.body)
  c.makeFunction(c.units.pop, astNode.name.value, astNode.lineNo.value, extraFlags)
  for deco in astNode.decorator_list:
    c.addOp(newArgInstr(OpCode.CallFunction, 1, deco.lineNo.value))
  c.addStoreOp(astNode.name.value, astNode.lineNo.value)


compileMethod ClassDef:
  for deco in astNode.decorator_list:
    c.compile(deco)
  let lineNo = astNode.lineNo.value
  c.addOp(OpCode.LoadBuildClass, lineNo)
  # class body function. In CPython this is more complicated because of metatype hooks,
  # treating it as normal function is a simpler approach
  c.units.add(newCompilerUnit(c.st, astNode, astNode.name.value))
  c.compileSeq(astNode.body)
  c.makeFunction(c.units.pop, astNode.name.value, lineNo)

  c.addLoadConst(astNode.name.value, astNode.lineNo.value)
  #[2+n args: 
      2: first for the code, second for the name
      n: for bases
  ]#
  let n = astNode.bases.len
  for base in astNode.bases:
    c.compile(base)
  c.addOp(newArgInstr(OpCode.CallFunction, 2+n, lineNo)) 
  for deco in astNode.decorator_list:
    c.addOp(newArgInstr(OpCode.CallFunction, 1, deco.lineNo.value))
  c.addStoreOp(astNode.name.value, lineNo)


compileMethod Return:
  if astNode.value.isNil:
    c.addLoadConst(pyNone, astNode.lineNo.value)
  else:
    c.compile(astNode.value)
  c.addOp(newInstr(OpCode.ReturnValue, astNode.lineNo.value))
  c.tcb.seenReturn = true


compileMethod Assign:
  assert astNode.targets.len == 1
  c.compile(astNode.value)
  c.compile(astNode.targets[0])

compileMethod AugAssign:
  c.compile(astNode.target)
  c.compile(astNode.value)
  let opCode = astNode.op.toInplaceOpCode
  c.addOp(newInstr(opCode, astNode.lineNo.value))

compileMethod Global: discard #c.addOp newInstr(CompileOpGlobal, astNode.lineNo.value)# discard#c.compileSeq astNode.names
compileMethod Nonlocal: discard#c.compileSeq astNode.names

compileMethod Delete:
  for i in astNode.targets:
    c.compile(i)

compileMethod For:
  assert astNode.orelse.len == 0
  let start = newBasicBlock(BlockType.For)
  let ending = newBasicBlock()
  # used in break stmt
  start.next = ending
  c.compile(astNode.iter)
  c.addOp(OpCode.GetIter, astNode.iter.lineNo.value)
  c.addBlock(start)
  c.addOp(newJumpInstr(OpCode.ForIter, ending, astNode.lineNo.value))
  c.compile(astNode.target)
  c.compileSeq(astNode.body)
  c.addOp(newJumpInstr(OpCode.JumpAbsolute, start, c.lastLineNo))
  c.addBlock(ending)

compileMethod While:
  assert astNode.orelse.len == 0
  let loop = newBasicBlock(BlockType.While)
  let ending = newBasicBlock()
  # used in break stmt
  loop.next = ending
  c.addBlock(loop)
  c.compile(astNode.test)
  c.addOp(newJumpInstr(OpCode.PopJumpIfFalse, ending, astNode.lineNo.value))
  c.compileSeq(astNode.body)
  c.addOp(newJumpInstr(OpCode.JumpAbsolute, loop, c.lastLineNo))
  c.addBlock(ending)


compileMethod If:
  let hasOrElse = 0 < astNode.orelse.len
  var next, ending: BasicBlock
  ending = newBasicBlock()
  if hasOrElse:
    next = newBasicBlock()
  else:
    next = ending
  # there is an optimization for `and` and `or` operators in the `test`.
  c.compile(astNode.test)
  c.addOp(newJumpInstr(OpCode.PopJumpIfFalse, next, astNode.lineNo.value))
  c.compileSeq(astNode.body)
  if hasOrElse:
    # for now JumpForward is the same as JumpAbsolute
    # because we have no relative jump yet
    # we only have absolute jump
    # we use jump forward just to keep in sync with
    # CPython implementation
    c.addOp(newJumpInstr(OpCode.JumpForward, ending, c.lastLineNo))
    c.addBlock(next)
    c.compileSeq(astNode.orelse)
  c.addBlock(ending)


compileMethod Raise:
  assert astNode.cause.isNil # should be blocked by ast
  if astNode.exc.isNil:
    c.addOp(newArgInstr(OpCode.RaiseVarargs, 0, astNode.lineNo.value))
  else:
    c.compile(astNode.exc)
    c.addOp(newArgInstr(OpCode.RaiseVarargs, 1, astNode.lineNo.value))


proc codegen_try_except(c: Compiler, astNode: AstTry) =
  assert astNode.orelse.len == 0, "not impl yet"
  assert 0 < astNode.handlers.len
  # the body here may not be necessary, I'm not sure. Add just in case.
  let body = newBasicBlock()
  var excpBlocks: seq[BasicBlock]
  for i in 0..<astNode.handlers.len:
    excpBlocks.add newBasicBlock()
  let ending = newBasicBlock()

  c.addBlock(body)
  # jump to exception handling if exception happens
  c.addOp(newJumpInstr(OpCode.SetupFinally, excpBlocks[0], astNode.lineNo.value))
  c.compileSeq(astNode.body)
  # no exception happens, jump to the ending
  c.addOp(newJumpInstr(OpCode.JumpAbsolute, ending, c.lastLineNo))

  for idx, handlerObj in astNode.handlers:
    let isLast = idx == astNode.handlers.len-1

    let handler = AstExcepthandler(handlerObj)
    let hLine = handler.lineno.value
    c.addBlock(excpBlocks[idx])
    let noAs = handler.name.isNil
    if handler.type.isNil:
      assert noAs
    else:
      # In CPython duptop is required, here we don't need that, because in each
      # exception match comparison we don't pop the exception, 
      # allowing further comparison
      # c.addop(OpCode.DupTop) 
      c.compile(handler.type)
      c.addop(newArgInstr(OpCode.CompareOp, int(CmpOp.ExcpMatch), hLine))
      if isLast:
        c.addop(newJumpInstr(OpCode.PopJumpIfFalse, ending, c.lastLineNo))
      else:
        c.addop(newJumpInstr(OpCode.PopJumpIfFalse, excpBlocks[idx+1], c.lastLineNo))
    if not noAs:
      # no need to `c.compile(handler.name)`
      #  as it's just a identifier
      c.addop(OpCode.DupTop, hLine)
      c.addStoreOp(handler.name, hLine)
    # now we are handling the exception, no need for future comparison
    c.addop(OpCode.PopTop, hLine)
    c.compileSeq(handler.body)
    if not noAs:
      #[name=None; del name  # Mark as artificial]#
      c.addLoadConst(pyNone, hLine)
      c.addStoreOp(handler.name, hLine)

      c.addDeleteOp(handler.name, hLine)
    # skip other handlers
    if not isLast:
      c.addop(newJumpInstr(OpCode.JumpAbsolute, ending, c.lastLineNo))

  let lastLineNo = c.lastLineNo
  c.addBlock(ending)
  c.addOp(OpCode.PopBlock, lastLineNo)

proc codegen_try_finally(c: Compiler, astNode: AstTry) =
  let curLine = astNode.lineNo.value

  let lastLineNo = c.lastLineNo
  let
    ending = newBasicBlock()
    exit = newBasicBlock()

  # `try` block
  c.addOp(newJumpInstr(OpCode.SetupFinally, ending, curLine))

  let body = newBasicBlock()
  c.addBlock(body)


  if astNode.handlers.len != 0:
    codegen_try_except(c, astNode)
  else:
    c.compileSeq astNode.body

  c.addop(newJumpInstr(OpCode.JumpAbsolute, exit, lastLineNo))

  # `finally` block
  c.addBlock(ending)
  c.compileSeq astNode.finalbody

  c.addBlock(exit)
  c.addOp(OpCode.PopBlock, lastLineNo)

compileMethod Try:
  if astNode.finalbody.len != 0:
    codegen_try_finally(c, astNode)
  else:
    codegen_try_except(c, astNode)


compileMethod Assert:
  if c.optimize > 0: return
  let lineNo = astNode.lineNo.value
  var ending = newBasicBlock()
  c.compile(astNode.test)
  c.addOp(newJumpInstr(OpCode.PopJumpIfTrue, ending, lineNo))
  c.addLoadOp(newPyAscii("AssertionError"), lineNo)
  if not astNode.msg.isNil:
    c.compile(astNode.msg)
    c.addOp(newArgInstr(OpCode.CallFunction, 1, lineNo))
  c.addOp(newArgInstr(OpCode.RaiseVarargs, 1, lineNo))
  c.addBlock(ending)


compileMethod Import:
  let lineNo = astNode.lineNo.value
  for n in astNode.names:
    let module = AstAlias(n)
    let name = module.name
    c.addOp(newArgInstr(OpCode.ImportName, c.tste.nameId(name.value), lineNo))
    c.addStoreOp(module.asname, lineNo)

compileMethod ImportFrom:
  let lineNo = astNode.lineNo.value
  let modName = astNode.module
  c.addOp(newArgInstr(OpCode.ImportName, c.tste.nameId(modName.value), lineNo))
  for n in astNode.names:
    let aliasNode = AstAlias(n)
    let name = aliasNode.name
    c.addOp(newArgInstr(OpCode.ImportFrom, c.tste.nameId(name.value), lineNo))
    c.addStoreOp(aliasNode.asname, lineNo)

compileMethod Expr:
  let lineNo = astNode.value.lineNo.value
  c.compile(astNode.value)
  if c.interactive:
    c.addOp(newInstr(OpCode.PrintExpr, lineNo))
  else:
    c.addOp(newInstr(OpCode.PopTop, lineNo))

compileMethod Pass:
  c.addOp(OpCode.NOP, astNode.lineNo.value)

template findNearestLoop(blockName) = 
  for basicBlock in c.tcu.blocks.reversed:
    if basicBlock.tp in {BlockType.For, BlockType.While}:
      blockName = basicBlock
      break
  if blockName.isNil:
    raiseSyntaxError("'break' outside loop", astNode)


compileMethod Break:
  var loopBlock: BasicBlock
  findNearestLoop(loopBlock)
  c.addOp(newJumpInstr(OpCode.JumpAbsolute, loopBlock.next, astNode.lineNo.value))


compileMethod Continue:
  var loopBlock: BasicBlock
  findNearestLoop(loopBlock)
  c.addOp(newJumpInstr(OpCode.JumpAbsolute, loopBlock, astNode.lineNo.value))


compileMethod BoolOp:
  let ending = newBasicBlock()
  let numValues = astNode.values.len
  var op: OpCode
  if astNode.op of AstAnd:
    op = OpCode.JumpIfFalseOrPop
  elif astNode.op of AstOr:
    op = OpCode.JumpIfTrueOrPop
  else:
    unreachable
  assert 1 < numValues
  for i in 0..<numValues:
    c.compile(astNode.values[i])
    if i != numValues - 1:
      c.addOp(newJumpInstr(op, ending, c.lastLineNo))
  c.addBlock(ending)


compileMethod BinOp:
  c.compile(astNode.left)
  c.compile(astNode.right)
  let opCode = astNode.op.toOpCode
  c.addOp(newInstr(opCode, astNode.lineNo.value))



compileMethod UnaryOp:
  c.compile(astNode.operand)
  let opCode = astNode.op.toOpCode
  c.addOp(newInstr(opCode, astNode.lineNo.value))

compileMethod Set:
  let n = astNode.elts.len
  for i in 0..<astNode.elts.len:
    c.compile(astNode.elts[i])
  var lineNo: int
  if astNode.elts.len == 0:
    lineNo = astNode.lineNo.value
  else:
    lineNo = c.lastLineNo
  c.addOp(newArgInstr(OpCode.BuildSet, n, lineNo))
  
template compileDictFromIt(c: Compiler; n: int; keyIt, valueIt; iter; lineNo: int) =
  for it{.inject.} in iter:
    c.compile(valueIt)
    c.compile(keyIt)
  c.addOp(newArgInstr(OpCode.BuildMap, n, lineNo))

compileMethod Dict:
  let n = astNode.values.len
  var lineNo: int
  if astNode.keys.len == 0:
    lineNo = astNode.lineNo.value
  else:
    lineNo = c.lastLineNo
  c.compileDictFromIt n, astNode.keys[it], astNode.values[it], 0..<astNode.keys.len, lineNo

compileMethod ListComp:
  let lineNo = astNode.lineNo.value
  assert astNode.generators.len == 1
  let genNode = AstComprehension(astNode.generators[0])
  c.units.add(newCompilerUnit(c.st, astNode, newPyAscii"<listcomp>"))
  # empty list
  let body = newBasicBlock()
  let ending = newBasicBlock()
  c.addOp(newArgInstr(OpCode.BuildList, 0, lineNo))
  c.addLoadOp(newPyAscii(".0"), astNode.lineNo.value) # the implicit iterator argument
  c.addBlock(body)
  c.addOp(newJumpInstr(OpCode.ForIter, ending, lineNo))
  c.compile(genNode.target)
  c.compile(astNode.elt)
  # 1 for the object to append, 2 for the iterator
  c.addOp(newArgInstr(OpCode.ListAppend, 2, lineNo))
  c.addOp(newJumpInstr(OpCode.JumpAbsolute, body, lineNo))
  c.addBlock(ending)
  c.addOp(OpCode.ReturnValue, lineNo)

  c.makeFunction(c.units.pop, newPyAscii("listcomp"), lineNo)
  # prepare the first arg of the function
  c.compile(genNode.iter)
  c.addOp(OpCode.GetIter, lineNo)
  c.addOp(newArgInstr(OpCode.CallFunction, 1, lineNo))


compileMethod Compare:
  assert astNode.ops.len == 1
  assert astNode.comparators.len == 1
  c.compile(astNode.left)
  c.compile(astNode.comparators[0])
  template addCmpOp(cmpTokenName) =
    c.addOp(newArgInstr(OpCode.COMPARE_OP, int(CmpOp.cmpTokenName), astNode.lineNo.value))
  case astNode.ops[0].kind
  of AsdlCmpOpTk.Lt:
    addCmpOp(Lt)
  of AsdlCmpOpTk.LtE:
    addCmpOp(Le)
  of AsdlCmpOpTk.Gt:
    addCmpOp(Gt)
  of AsdlCmpOpTk.GtE:
    addCmpOp(Ge)
  of AsdlCmpOpTk.Eq:
    addCmpOp(Eq)
  of AsdlCmpOpTk.NotEq:
    addCmpOp(Ne)
  of AsdlCmpOpTk.In:
    addCmpOp(In)
  of AsdlCmpOpTk.NotIn:
    addCmpOp(NotIn)
  else:
    unreachable

proc validate_keywords(c: Compiler, keywords: seq[Asdlkeyword]; baseAst: AstCall) =
  ## codegen_validate_keywords
  var has = newPySet()
  for kw in keywords:
    if kw.arg.isNil: continue  # when will be nil?
    let name = kw.arg.value
    if has.containsOrIncl name:
      FormatPyObjectError!!raiseSyntaxError(
        &"keyword argument repeated: {name:U}", baseAst)

compileMethod Call:
  let kwL = astNode.keywords.len
  var op: OpCode
  if kwL == 0:
    op = Opcode.CallFunction
  else:
    let lineNo = astNode.lineNo.value
    template compile(c: Compiler; dictKey: PyStrObject) =
      c.addLoadConst dictKey, lineNo
    # firstly push kw as a dict
    c.validate_keywords astNode.keywords, astNode
    c.compileDictFromIt kwL, it.arg.value, it.value, astNode.keywords, lineNo
    op = OpCode.CallFunction_EX

  c.compile(astNode.fun)
  for arg in astNode.args:
    c.compile(arg)
  c.addOp(newArgInstr(op, astNode.args.len, astNode.lineNo.value))


compileMethod Attribute:
  let lineNo = astNode.lineNo.value
  c.compile(astNode.value)
  let opArg = c.tste.nameId(astNode.attr.value)
  if astNode.ctx of AstLoad:
    c.addOp(newArgInstr(OpCode.LoadAttr, opArg, lineNo))
  elif astNode.ctx of AstStore:
    c.addOp(newArgInstr(OpCode.StoreAttr, opArg, lineNo))
  elif astNode.ctx of AstDel:
    c.addOp(newArgInstr(OpCode.DeleteAttr, opArg, lineNo))
  else:
    unreachable

compileMethod Subscript:
  let lineNo = astNode.lineNo.value
  if astNode.ctx of AstLoad:
    c.compile(astNode.value)
    c.compile(astNode.slice)
    c.addOp(OpCode.BinarySubscr, lineNo)
  elif astNode.ctx of AstStore:
    c.compile(astNode.value)
    c.compile(astNode.slice)
    c.addOp(OpCode.StoreSubscr, lineNo)
  elif astNode.ctx of AstDel:
    c.compile(astNode.value)
    c.compile(astNode.slice)
    c.addOp(OpCode.DeleteSubscr, lineNo)
  else:
    unreachable
  

compileMethod Constant:
  c.tcu.addLoadConst(astNode.value.value, astNode.lineNo.value)


compileMethod Name:
  let lineNo = astNode.lineNo.value
  if astNode.ctx of AstLoad:
    c.addLoadOp(astNode.id, lineNo)
  elif astNode.ctx of AstStore:
    c.addStoreOp(astNode.id, lineNo)
  elif astNode.ctx of AstDel:
    c.addDeleteOp(astNode.id, lineNo)
  else:
    unreachable # no other context implemented


compileMethod List:
  for elt in astNode.elts:
    c.compile(elt)
  var lineNo: int
  if astNode.elts.len == 0:
    lineNo = astNode.lineNo.value
  else:
    lineNo = c.lastLineNo
  c.addOp(newArgInstr(OpCode.BuildList, astNode.elts.len, lineNo))

compileMethod Tuple:
  case astNode.ctx.kind
  of AsdlExprContextTk.Load:
    for elt in astNode.elts:
      c.compile(elt)
    var lineNo: int
    if astNode.elts.len == 0:
      lineNo = astNode.lineNo.value
    else:
      lineNo = c.lastLineNo
    c.addOp(newArgInstr(OpCode.BuildTuple, astNode.elts.len, lineNo))
  of AsdlExprContextTk.Store:
    c.addOp(newArgInstr(OpCode.UnpackSequence, astNode.elts.len, astNode.lineNo.value))
    for elt in astNode.elts:
      c.compile(elt)
  else:
    unreachable

compileMethod Slice:
  let lineNo = c.lastLineNo
  var n = 2

  if astNode.lower.isNil:
    c.addLoadConst(pyNone, lineNo)
  else:
    c.compile(astNode.lower)

  if astNode.upper.isNil:
    c.addLoadConst(pyNone, lineNo)
  else:
    c.compile(astNode.upper)

  if not astNode.step.isNil:
    c.compile(astNode.step)
    inc n

  c.addOp(newArgInstr(OpCode.BuildSlice, n, lineNo))

compileMethod Index:
  c.compile(astNode.value)

compileMethod Arguments:
  unreachable()

template compile*(tastRoot: AsdlModl, fileNameV: PyStrObject|string, flags=initPyCompilerFlags(), optimize = -1): PyObject = 
  bind newPyStr, fromBltinSyntaxError, assemble, compile
  let fileName = newPyStr fileNameV
  var c: Compiler
  try:
    let astRoot = tastRoot
    c = newCompiler(astRoot, fileName, flags, optimize)
    c.compile(astRoot)
  except SyntaxError as e:
    return fromBltinSyntaxError(e, fileName)
  c.tcu.assemble(c.fileName)

proc compile*(input, fileName: PyStrObject|string, flags=initPyCompilerFlags(), optimize = -1): PyObject{.raises: [].} =
  compile ast($input, $fileName),
    fileName, flags, optimize

proc compile*(input: ParseNode, fileName: PyStrObject|string, flags=initPyCompilerFlags(), optimize = -1): PyObject{.raises: [].} =
  compile ast(input),
    fileName, flags, optimize
