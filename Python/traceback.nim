import strformat
import strutils
import algorithm

import ../Objects/bundle
import ../Parser/lexer
import ../Utils/compat


proc fmtTraceBack(tb: TraceBack): string = 
  assert tb.fileName.ofPyStrObject
  # lineNo should starts from 1. 0 means not initialized properly
  assert tb.lineNo != 0
  let fileName = $PyStrObject(tb.fileName).str
  var atWhere: string
  if tb.funName.isNil:
    atWhere = ""
  else:
    assert tb.funName.ofPyStrObject
    atWhere = $(newPyAscii", in " & PyStrObject(tb.funName))
  result &= fmt("  File \"{fileName}\", line {tb.lineNo}{atWhere}\n")
  result &= "    " & getSource(fileName, tb.lineNo).strip(chars={' '})
  if tb.colNo != -1:
    result &= "\n    " & "^".indent(tb.colNo)


proc printTb*(excp: PyExceptionObject) = 
  var cur = excp
  var excpStrs: seq[string]
  while not cur.isNil:
    var singleExcpStrs: seq[string]
    singleExcpStrs.add "Traceback (most recent call last):"
    for tb in cur.traceBacks.reversed:
      singleExcpStrs.add tb.fmtTraceBack
    singleExcpStrs.add $PyStrObject(tpMagic(BaseError, repr)(cur)).str
    excpStrs.add singleExcpStrs.join("\n")
    cur = cur.context
  let joinMsg = "\n\nDuring handling of the above exception, another exception occured\n\n"
  echoCompat excpStrs.reversed.join(joinMsg)
