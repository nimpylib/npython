import strformat
import strutils
import algorithm

import ../Objects/[
  pyobject,
  exceptionsImpl,
  stringobject,
]
import ../Objects/numobjects/intobject_decl
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
  var cur: PyBaseExceptionObject = excp
  var excpStrs: seq[string]
  while not cur.isNil:
    var singleExcpStrs: seq[string]
    singleExcpStrs.add "Traceback (most recent call last):"
    for tb in cur.traceBacks.reversed:
      singleExcpStrs.add tb.fmtTraceBack
    let msg = $PyStrObject(tpMagic(BaseError, str)(cur)).str
    var head = cur.pyType.name
    if msg.len > 0:
      head.add ": "
      head.add msg
    singleExcpStrs.add head
    excpStrs.add singleExcpStrs.join("\n")
    cur = cur.context
  let joinMsg = "\n\nDuring handling of the above exception, another exception occured\n\n"
  errEchoCompat excpStrs.reversed.join(joinMsg)

declarePyType Traceback():
  #TODO:traceback
  #tb_next: PyTracebackObject
  #tb_frame: PyFrameObject
  #tb_lasti{.member, readonly.}: PyIntObject
  tb_lineno{.member, readonly.}: PyIntObject

proc newPyTraceback*(t: TraceBack): PyTracebackObject =
  result = newPyTracebackSimple()
  #result.colon = newPyInt t.colNo
  result.tb_lineno = newPyInt t.lineNo
