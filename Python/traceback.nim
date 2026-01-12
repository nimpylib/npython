import std/strformat

import ../Include/cpython/pyerrors
import ../Include/cpython/critical_section
import ../Objects/[
  pyobject,
  exceptionsImpl,
  noneobject,
  stringobjectImpl,
  codeobject,
  frameobject,
]
import ../Objects/exceptions/ioerror
import ../Objects/numobjects/intobject
import ../Objects/numobjects/intobject/ops
import ./sysmodule/attrs
import ../Parser/lexer
import ../Utils/compat

using f: PyObject ## std stream e.g. stderr

template PyFile_WritelineString*(s: string; f): untyped =
  #TODO:io
  bind newIOError
  discard f
  try:
    errEchoCompat s
    PyBaseErrorObject(nil)
  except IOError as e:
    newIOError e
template PyFile_WritelineString*(s: cstring; f): untyped =
  PyFile_WritelineString $s, f

template safePyFile_WriteString(s) =
  result.add s
#template safePyFile_WriteString(s: cstring) = safePyFile_WriteString $s

#proc Py_WriteIndent(indent: int, f): bool =
proc Py_WriteIndent(indent: int): string =
  ## `_Py_WriteIndent`
  var indent = indent
  let buf10 = "          "
  while indent > 0:
    var n = if indent < 10: indent else: 10
    let chunk = buf10[0 ..< n]
    safePyFile_WriteString chunk
    indent -= 10

#[
#proc Py_WriteIndentedMargin*(indent: int, margin; f): bool =
proc Py_WriteIndentedMargin*(indent: int, margin): string =
  ## `_Py_WriteIndentedMargin`
  result.add Py_WriteIndent(indent)
  if margin != nil:
    safePyFile_WriteString margin
]#

proc display_source_lineNotNil(f; filename_obj: PyStrObject, lineno, indent: int;
                  #margin_indent; margin;
                  truncation: var int, line: var PyStrObject): PyBaseErrorObject =

  # open the file
  if filename_obj.len == 0:
    return

  #TODO:io
  when declared(openFileCompat):
    let fileName = $filename_obj.str
    # Do not attempt to open things like <string> or <stdin>
    let len = fileName.len
    if len >= 2 and (fileName[0] == '<') and fileName[^1] == '>':
      return

  # Try to get the source line using existing helper
  var lineobj: PyStrObject
  retIfExc getSource(filename_obj, lineno, lineobj)
  #if src.isNil or not src.ofPyStrObject: return

  let L = lineobj.len

  line = lineobj

  # remove leading indentation (spaces, tabs, form feed)
  var i = 0
  while i < L:
    let c = lineobj[i]
    if Rune(high char) <% c: break
    if char(c) not_in {' ', '\t', '\12'}:
      break
    inc i
  
  if i > 0:
    lineobj = lineobj.substringUnsafe(i, L)

  truncation = i - indent

  var outs: string
  # Write some spaces before the line
  outs.add Py_WriteIndent(indent)

  # finally display the line
  outs.add $lineobj.str

  retIfExc PyFile_WritelineString(outs, f)

proc display_source_line(f; filename: PyStrObject, lineno, indent: int;
                  #margin_indent: int, margin;
                  truncation: var int, line: var PyStrObject): PyBaseErrorObject =
  if filename.isNil:
    return
  return display_source_lineNotNil(f, filename, lineno, indent,
                     #margin_indent, margin,
                     truncation, line)

proc Py_DisplaySourceLine*(f; filename: PyObject, lineno, indent: int;
                  #margin_indent: int, margin;
                  truncation: var int, line: var PyStrObject): PyBaseErrorObject =
  ## overload: accept filename as PyObject (unicode) and delegate to string variant
  if filename.isNil:
    return
  assert filename.ofPyStrObject
  let fname = PyStrObject(filename)
  return display_source_lineNotNil(f, fname, lineno, indent,
                     #margin_indent, margin,
                     truncation, line)


proc Py_DisplaySourceLine*(f; filename: PyStrObject, lineno, indent: int;
                  #margin_indent: int, margin;
                  truncation: var int, line: var PyStrObject): PyBaseErrorObject =
  ## `_Py_DisplaySourceLine`
  return display_source_line(f, filename, lineno, indent,
                     truncation, line)

const TRACEBACK_SOURCE_LINE_INDENT = 4

proc ignore_source_errors(exc: PyBaseExceptionObject): bool =
  if exc.isNil:
    return false
  if exc.isThrownException:
    if exc.ofPyKeyboardInterruptObject:
      return true

#[
#proc Py_byte_offset_to_character_offset(source_line: PyStrObject, byte_offset: int): int
  # `_PyPegen_byte_offset_to_character_offset`
  var i = byte_offset

  while i <
  runeLenAt(i)
]#
proc tb_displayline(tb: PyTracebackObject, f; filename: PyStrObject,
          lineno: int, frame: PyFrameObject, name: PyObject,
          #margin_indent: int, margin
          ): PyBaseErrorObject =
  if filename.isNil or name.isNil: return

  var line: string
  #line.add Py_WriteIndentedMargin(margin_indent, margin)

  let
    filenameS = $filename.str
    name = $PyStrObject(name).str
  line.add &"  File \"{filenameS}\", line {lineno}, in {name}"

  retIfExc PyFile_WritelineString(line, f) # , Py_PRINT_RAW)

  var truncation = TRACEBACK_SOURCE_LINE_INDENT
  var source_line: PyStrObject = nil


  result = display_source_line(
          f, filename, lineno, TRACEBACK_SOURCE_LINE_INDENT,
          truncation, source_line);
  if not result.isNil or source_line.isNil:
    # ignore errors since we can't report them, can we?
    if ignore_source_errors(result):
      return nil

const TB_RECURSIVE_CUTOFF = 3


proc tb_print_line_repeated(f; cnt: int): PyBaseErrorObject =
    var cnt = cnt
    cnt -= TB_RECURSIVE_CUTOFF
    var line = fmt"[Previous line repeated {cnt} more time"
    if cnt > 1: line.add 's'
    line.add ']'

    result = PyFile_WritelineString(line, f)

proc tb_printinternal(tb: PyTracebackObject, f; limit: int): PyBaseErrorObject{.raises: [].} =
  var depth = 0
  var last_file: PyStrObject = nil
  var last_line = -1
  var last_name: PyStrObject = nil
  var cnt = 0

  var tb = tb
  var tb1 = tb
  while tb1 != nil:
    inc depth
    tb1 = tb1.tb_next_may_nil

  while tb != nil and depth > limit:
    dec depth
    tb = tb.tb_next_may_nil
  while tb != nil:
    let frame = PyFrameObject(tb.tb_frame)
    let code = frame.code
    let tb_lineno = tb.tb_lineno
    if last_file.isNil or
       code.fileName != last_file or
       last_line == -1 or tb_lineno != last_line or
       last_name.isNil or code.codeName != last_name:
      if cnt > TB_RECURSIVE_CUTOFF:
        retIfExc tb_print_line_repeated(f, cnt)
      last_file = code.fileName
      last_line = tb_lineno
      last_name = code.codeName
      cnt = 0

    inc cnt
    if cnt <= TB_RECURSIVE_CUTOFF:
      retIfExc tb_displayline(tb, f, code.fileName, tb_lineno,
                        frame, code.codeName#, indent, margin
                        )
      #TODO:PyErr_CheckSignals
      when declared(PyErr_CheckSignals):
        retIfExc PyErr_CheckSignals()  #TODO:signal

    tb = tb.tb_next_may_nil

  if cnt > TB_RECURSIVE_CUTOFF:
    retIfExc tb_print_line_repeated(f, cnt)

const PyTraceBack_LIMIT = 1000

proc PyTraceBack_Print_with_noNL_header*(
    v: PyTracebackObject,
    #indent: int, margin; header_margin: cstring,
    header: cstring,
    f: PyObject): PyBaseErrorObject{.raises: [].} =
  ## `_PyTraceBack_Print`
  var limit: int = PyTraceBack_LIMIT

  if v.isNil: return

  if not v.ofPyTraceBackObject():
    return PyErr_BadInternalCall()

  let limitObj = PySys_GetObject("tracebacklimit")
  if not limitObj.isNil and limitObj.ofPyIntObject:
    var overflow: IntSign
    let lv = PyIntObject(limitObj).toInt(overflow)
    if overflow == IntSign.Positive:
      limit = high int # 0x7FFFFFFF
    elif lv <= 0:
      return
    else:
      limit = lv

  var outs: string

  #outs.add Py_WriteIndentedMargin(indent, header_margin)

  outs.add header

  retIfExc PyFile_WritelineString(outs, f)

  retIfExc tb_printinternal(v, f, limit)


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
