

import std/strutils
import ../../Parser/lexer
import ../[
  pyobject,
  stringobject,
  exceptions,
  codeobject,
]
import ../../Python/[opcode]

#{.experimental: "views".}
type
  PyCodeAddressRange_Opaque = object
    lo_next: ptr int
    limit_size: int
    computed_line: int
  PyCodeAddressRange* = object
    ar_start*, ar_end*, ar_line*: int
    opaque: PyCodeAddressRange_Opaque



using self: var PyCodeAddressRange
using linetable: openArray[int]
using pLoNext: ptr int

proc get_line_delta(pLoNext): int = pLoNext[]  #TODO:PY_CODE_LOCATION

proc initAddressRange*(self; linetable; firstlineno: int) =
  ## `_PyLineTable_InitAddressRange`
  # store a copy of the provided openArray so we can index it safely
  self.opaque.lo_next = addr linetable[0]
  self.opaque.limit_size = linetable.len
  self.ar_start = -1
  self.ar_end = 0
  self.opaque.computed_line = firstlineno
  self.ar_line = -1;

proc checkLineNumber(self; lasti: int): int =
  ## [`_PyCode_CheckLineNumber`]
  ## Update `self` to describe the first and one-past-the-last
  ## instructions that have the same source line as `lasti`.
  ## Return that line number, or -1 if `lasti` is out of bounds.
  if lasti < 0 or lasti >= self.opaque.limit_size:
    return -1

  let pseq = self.opaque.lo_next
  template `[]`(p: ptr int, i: int): int =
    cast[ptr int](cast[int](p) + i)[]

  # read the target line for the given address
  let target = pseq[lasti]

  # find the first index with this line
  var i = lasti
  while i >= 0 and pseq[i] == target:
    dec i
  self.ar_start = i + 1

  # find the one-past-last index with this line
  i = lasti
  while i < self.opaque.limit_size and pseq[i] == target:
    inc i
  self.ar_end = i

  self.ar_line = target
  result = self.ar_line

proc initAddressRange*(self: var PyCodeAddressRange, co: PyCodeObject) =
  ## `_PyCode_InitAddressRange`
  assert co.lineNos.len > 0
  self.initAddressRange(co.lineNos, co.firstlineno)

proc retreat(self: var PyCodeAddressRange) =
  ## Move the bounds to the start of the current range.
  ## In this simplified implementation this is a no-op because
  ## `checkLineNumber` already set `ar_start`/`ar_end`.
  discard
proc advance_with_locations(self; end_line, start_column, end_column: var int) =
  ## Populate the provided vars with location information derived from
  ## the current address range. Columns are not computed here so they are
  ## set to 0.
  end_line = self.ar_line
  start_column = 0
  end_column = 0

proc addr2location*(code: PyCodeObject, addrq: int,
  start_line, start_column, end_line, end_column: var int): PyBaseErrorObject =
  ## PyCode_Addr2Location
  ## Populate the caller-provided vars with a best-effort source
  ## location for bytecode address `addrq` by inspecting the
  ## bytecode instruction and scanning the source file for a
  ## matching token. Falls back to a conservative whole-line span.
  if addrq < 0:
    end_line = code.firstlineno
    start_line = end_line
    start_column = 0
    end_column = 0
    return nil

  if addrq >= code.lineNos.len or addrq < 0:
    start_line = -1
    start_column = -1
    end_line = -1
    end_column = -1
    return nil

  let ln = code.lineNos[addrq]
  start_line = ln
  end_line = ln

  # If filename not available or is a synthetic name, fall back.
  let fname = $code.fileName
  if fname.len == 0 or fname[0] == '<':
    start_column = 0
    end_column = start_column + 1
    return nil

  var sourceLine = ""
  case getSource(fname, ln, sourceLine)
  of GSR_Success:
    discard
  else:
    start_column = 0
    end_column = start_column + 1
    return nil

  # emulate the leading-whitespace trimming done by `display_source_line`
  # so returned byte offsets are relative to the trimmed line used by
  # the traceback display logic.
  proc isAsciiWhitespace(c: char): bool = c in {' ', '\t', '\f'}
  var leadBytes = 0
  while leadBytes < sourceLine.len:
    let ch = sourceLine[leadBytes]
    if ord(ch) >= 128: break
    if not isAsciiWhitespace(ch): break
    inc leadBytes

  # Pick a token to search for based on the opcode at addrq.
  var tokenToFind: string = ""
  let instr = code.code[addrq]
  let opc = OpCode(instr[0])
  let oparg = instr[1]

  case opc
  of OpCode.LoadName, OpCode.StoreName, OpCode.DeleteName,
     OpCode.LoadGlobal, OpCode.StoreGlobal, OpCode.DeleteGlobal,
     OpCode.LoadAttr:
    if oparg >= 0 and oparg < code.names.len:
      tokenToFind = $code.names[oparg]
  of OpCode.LoadFast, OpCode.StoreFast, OpCode.DeleteFast:
    if oparg >= 0 and oparg < code.localVars.len:
      tokenToFind = $code.localVars[oparg]
  of OpCode.LoadDeref, OpCode.StoreDeref, OpCode.DeleteDeref:
    if oparg >= 0:
      if oparg < code.cellVars.len:
        tokenToFind = $code.cellVars[oparg]
      else:
        let idx = oparg - code.cellVars.len
        if idx >= 0 and idx < code.freeVars.len:
          tokenToFind = $code.freeVars[idx]
  of OpCode.LoadConst:
    if oparg >= 0 and oparg < code.constants.len:
      let co = code.constants[oparg]
      if co.ofPyStrObject:
        tokenToFind = $PyStrObject(co)
      else:
        tokenToFind = $co
  else:
    discard

  if tokenToFind.len > 0:
    let trimmedLine = sourceLine[leadBytes ..< sourceLine.len]
    proc isIdentChar(c: char): bool =
      if ord(c) < 128:
        return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
      else:
        # Treat non-ascii as identifier-capable (best-effort for unicode ids)
        return true

    var searchPos = 0
    while true:
      let pos = trimmedLine.find(tokenToFind, searchPos)
      if pos < 0: break
      let beforeOk = pos == 0 or not isIdentChar(trimmedLine[pos - 1])
      let afterIdx = pos + tokenToFind.len
      let afterOk = afterIdx >= trimmedLine.len or not isIdentChar(trimmedLine[afterIdx])
      if beforeOk and afterOk:
        start_column = pos
        end_column = if pos + tokenToFind.len <= trimmedLine.len: pos + tokenToFind.len else: trimmedLine.len
        return nil
      searchPos = pos + 1
    # If we didn't find a boundary-respecting occurrence, fall back to first occurrence
    let firstPos = trimmedLine.find(tokenToFind)
    if firstPos >= 0:
      start_column = firstPos
      end_column = if firstPos + tokenToFind.len <= trimmedLine.len: firstPos + tokenToFind.len else: trimmedLine.len
      return nil

  # fallback: use the full trimmed source line length as the end column
  start_column = 0
  end_column = sourceLine.len - leadBytes
  return nil


