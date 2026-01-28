import std/strformat

import ./[pyobject,
  exceptions,
  stringobject,
  byteobjects,
]
import ../Include/ceval
import ./numobjects/intobject_decl
import ../Python/[opcode, symtable]

type
  OpArg* = int

declarePyType Code(tpToken):
    # for convenient and not performance critical accessing
    code: seq[(OpCode, OpArg)]
    lineNos: seq[int]
    constants{.member"co_consts", readonly.}: seq[PyObject]

    # store the strings for exception and debugging infomation
    names{.member"co_names", readonly.}: seq[PyStrObject]
    localVars{.member"co_varnames", readonly.}: seq[PyStrObject]
    cellVars{.member"co_cellvars", readonly.}: seq[PyStrObject]
    freeVars{.member"co_freevars", readonly.}: seq[PyStrObject]

    argNames: seq[PyStrObject]
    argScopes: seq[(Scope, int)]
    varArgName: PyStrObject  ## name of *args parameter if present
    kwOnlyNames: seq[PyStrObject]
    kwOnlyDefaults: seq[PyObject]

    # for tracebacks
    codeName{.member"co_name", readonly.}: PyStrObject
    fileName{.member"co_filename", readonly.}: PyStrObject

    # cache
    code_adaptive_cached{.private.}: PyBytesObject
    code_len_when_last_cached{.private.}: int

    #TODO:code.co_flags
    flags{.member"co_flags", readonly.}: int  # no use yet

template genIntGetter(pureName, seqAttr){.dirty.} =
  proc pureName*(self: PyCodeObject): int{.inline.} = self.seqAttr.len
  genProperty Code, "co_" & astToStr(pureName), pureName, newPyInt self.pureName

genIntGetter argcount, argScopes
genIntGetter kwonlyargcount, kwOnlyNames
genIntGetter nlocals, localVars

proc firstlineno*(self: PyCodeObject): int{.inline.} =
  # Needed?
  #if self.lineNos.len == 0: return 0
  return self.lineNos[0]
genProperty Code, "co_firstlineno", firstlineno, newPyInt self.firstlineno
static: assert OpCode.high.BiggestInt <= char.high.BiggestInt
proc code_adaptiveImpl(self: PyCodeObject): seq[char] =
  result = newSeqOfCap[char](2*self.code.len)
  template push(i) = result.add cast[char](i)
  for (ocode, oarg) in self.code:
    push ocode
    if oarg > OpArg 0:
      push oarg
    push 0
proc code_adaptive*(self: PyCodeObject): PyBytesObject =
  let curLen = self.code.len
  if curLen == self.code_len_when_last_cached: return self.code_adaptive_cached
  result = newPyBytes self.code_adaptiveImpl
  self.code_adaptive_cached = result
  self.code_len_when_last_cached = curLen

genProperty Code, "co_code", code, self.code_adaptive

# most attrs of code objects are set in compile.nim
proc newPyCode*(codeName, fileName: PyStrObject, length: int): PyCodeObject =
  result = newPyCodeSimple()
  result.code = newSeqOfCap[(OpCode, OpArg)] length
  result.codeName = codeName
  result.fileName = fileName

proc len*(code: PyCodeObject): int {. inline .} = 
  code.code.len

proc addOpCode*(code: PyCodeObject, 
               instr: tuple[opCode: OpCode, opArg: OpArg, lineNo: int]) = 
  code.code.add((instr.opCode, instr.opArg))
  code.lineNos.add(instr.lineNo)

implCodeMagic repr:
  let codeName = self.codeName.str
  let fileName = self.fileName.str
  let msg = fmt("<code object {codeName} at {self.idStr}, file \"{fileName}\">")
  newPyStr(msg)

proc toStringBy*(t: tuple[opCode: OpCode, opArg: OpArg], 
                 code: PyCodeObject,
                 otherCodes: var seq[PyCodeObject]): string =
  ## unstable
  ## 
  ## Return a string representation of a single bytecode instruction.
  let (opCode, opArg) = t
  block:
    var line = fmt"{opCode:<30}"
    if opCode in hasArgSet:
      line &= fmt"{opArg:<4}"
      case opCode
      of OpCode.LoadName, OpCode.StoreName, OpCode.DeleteName, OpCode.LoadAttr,
        OpCode.LoadGlobal, OpCode.StoreGlobal, OpCode.DeleteGlobal:
        line &= fmt" ({code.names[opArg]})"
      of OpCode.LoadConst:
        let constObj = code.constants[opArg]
        if constObj.ofPyCodeObject:
          let otherCode = PyCodeObject(constObj)
          otherCodes.add(otherCode)
          let reprStr = tpMagic(Code, repr)(otherCode)
          line &= fmt" ({reprStr})"
        else:
          line &= fmt" ({code.constants[opArg]})"
      of OpCode.LoadFast, OpCode.StoreFast, OpCode.DeleteFast:
        line &= fmt" ({code.localVars[opArg]})"
      of OpCode.LoadDeref, OpCode.StoreDeref, OpCode.DeleteDeref:
        if opArg < code.cellVars.len:
          line &= fmt" ({code.cellVars[opArg]})"
        else:
          line &= fmt" ({code.freeVars[opArg - code.cellVars.len]})"
      of OpCode.CallFunction, OpCode.CallFunction_EX, jumpSet, OpCode.BuildList, 
         OpCode.BuildTuple, OpCode.UnpackSequence, OpCode.MakeFunction,
         OpCode.RaiseVarargs, OpCode.ReRaise, OpCode.Swap:
        discard
      of OpCode.LoadSpecial:
        line &= fmt" ({getSpecialFromOpArg(opArg).name})"
      else:
        line &= " (Unknown OpCode)"
    line

method `$`*(code: PyCodeObject): string{.raises: [].} = 
  result.add("Names: " & $code.names)
  result.add("Local variables: " & $code.localVars)
  result.add("Cell variables: " & $code.cellVars)
  result.add("Free variables: " & $code.freeVars)
  # temperary workaround for code obj in the disassembly
  var otherCodes: seq[PyCodeObject]
  for idx, opArray in code.code:
    result.add(&"{idx:>10} " & opArray.toStringBy(code, otherCodes))
    result.add('\n')
  for otherCode in otherCodes:
    result &= $otherCode

when not defined(release):
  # EXT. for debug
  implCodeMethod "_npython_repr": newPyStr $self
