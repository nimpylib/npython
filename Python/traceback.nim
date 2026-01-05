import strformat
import strutils
import algorithm

import ../Include/cpython/critical_section
import ../Objects/[
  pyobject,
  exceptionsImpl,
  noneobject,
  stringobjectImpl,
  codeobject,
  frameobject,
]
import ../Parser/lexer
import ../Utils/compat

const
  EXCEPTION_TB_HEADER_noNL* = "Traceback (most recent call last):"  #XXX: like CPython ERROR_TB_HEADER but no newline
  #EXCEPTION_GROUP_TB_HEADER_noNL* = "Exception Group Traceback (most recent call last):"  #XXX: like CPython ERROR_GROUP_TB_HEADER but no newline

proc traceback*(excp: PyBaseExceptionObject): PyTracebackObject =
  ## `PyException_GetTraceback`
  PyTracebackObject excp.privateGetTracebackRef

proc `traceback=`*(excp: PyBaseExceptionObject; tb: PyTracebackObject) =
  ## `PyException_SetTraceback`
  assert not tb.isNil
  excp.privateGetTracebackRef = tb

proc `traceback=`*(excp: PyBaseExceptionObject; tb: PyNoneObject) =
  ## `PyException_SetTraceback`
  excp.privateGetTracebackRef = nil

proc setTraceback*(excp: PyBaseExceptionObject; tb: PyObject): PyBaseErrorObject =
  ## `PyException_SetTraceback`
  if tb.isNil:
    return newTypeError newPyAscii"__traceback__ may not be deleted"
  if tb.ofPyTracebackObject:
    excp.traceback = PyTracebackObject tb
  elif tb.isPyNone:
    excp.traceback = pyNone
  else:
    return newTypeError newPyAscii"__traceback__ must be a traceback or None"

proc getTrackback*(self: PyBaseExceptionObject): PyObject =
  ## get the traceback object from exception
  self.privateGetTracebackRef.nil2none

methodMacroTmpl(BaseException)
genProperty BaseException, "__traceback__", traceback, self.getTrackback:
  result = self.setTraceback other

methodMacroTmpl(Exception)
genProperty Exception, "__traceback__", traceback, self.getTrackback:
  criticalWrite(self):
    result = self.setTraceback other

proc fmtTraceBack(tb: PyTraceBackObject): string = 
  let f = PyFrameObject(tb.tb_frame)
  let code = f.code
  let fileName = $code.fileName.str
  var source = ""
  # lineNo should starts from 1. 0 means not initialized properly
  let lineno = tb.tb_lineno
  let ret = getSource(fileName, lineno, source)
  case ret
  of GSR_Success:
    discard
  of GSR_LineNoNotSet:
    source = "<no source line available>"
  of GSR_LineNoOutOfRange:
    source = &"<no source line available (line number {lineno} out of range {source})>"
  of GSR_NoSuchFile:
    source = "<no source line available (file not found)>"

  var atWhere: string
  if code.codeName.isNil:
    atWhere = ""
  else:
    atWhere = $(newPyAscii", in " & code.codeName)
  result &= fmt("  File \"{fileName}\", line {lineno}{atWhere}\n")
  result &= "    " & source.strip(chars={' '})
  if tb.colNo != -1:
    result &= "\n    " & "^".indent(tb.colNo)

proc printTb*(excp: PyExceptionObject) = 
  var cur: PyBaseExceptionObject = excp
  var excpStrs: seq[string]
  while not cur.isNil:
    var singleExcpStrs: seq[string]
    singleExcpStrs.add "Traceback (most recent call last):"
    var curTb = cur.traceback
    while not curTb.isNil:
      singleExcpStrs.add curTb.fmtTraceBack
      curTb = curTb.tb_next_may_nil
    let msg = $PyStrObject(tpMagic(BaseException, str)(cur)).str
    var head = cur.typeName
    if msg.len > 0:
      head.add ": "
      head.add msg
    singleExcpStrs.add head
    excpStrs.add singleExcpStrs.join("\n")
    cur = cur.context
  excpStrs.reverse
  errEchoCompat excpStrs.join("\n\nDuring handling of the above exception, another exception occured\n\n")
