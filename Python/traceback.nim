from std/unicode import size
import std/strformat

import ../Include/cpython/pyerrors
import ../Include/cpython/critical_section
import ../Include/cpython/compile
import ../Objects/[
  pyobject,
  exceptionsImpl,
  noneobject,
  stringobjectImpl,
  codeobject,
  frameobject,
]
import ../Objects/codeobject/locApis
import ../Objects/exceptions/ioerror
import ../Objects/numobjects/intobject
import ../Objects/numobjects/intobject/ops
import ./sysmodule/attrs
import ../Parser/[lexer, apis]
import ../Python/[asdl]
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

# We use implementation since https://github.com/python/cpython/pull/29207
#  but do not apply removal for margin from https://github.com/python/cpython/issues/110721

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

using
  margin: cstring
  margin_indent: int

proc Py_WriteIndentedMargin*(indent: int, margin): string =
  ## `_Py_WriteIndentedMargin`
  result.add Py_WriteIndent(indent)
  if margin != nil:
    safePyFile_WriteString margin

func IS_WHITESPACE(c: char): bool{.inline.} = c in {' ', '\t', '\f'}

proc display_source_lineNotNil(f; filename_obj: PyStrObject, lineno, indent: int;
                  margin_indent; margin;
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
    if not IS_WHITESPACE(char(c)):
      break
    inc i
  
  if i > 0:
    lineobj = lineobj.substringUnsafe(i, L)

  truncation = i - indent

  var outs: string
  outs.add Py_WriteIndentedMargin(margin_indent, margin)

  # Write some spaces before the line
  outs.add Py_WriteIndent(indent)

  # finally display the line
  outs.add $lineobj.str

  retIfExc PyFile_WritelineString(outs, f)

proc display_source_line(f; filename: PyStrObject, lineno, indent: int;
                  margin_indent; margin;
                  truncation: var int, line: var PyStrObject): PyBaseErrorObject =
  if filename.isNil:
    return
  return display_source_lineNotNil(f, filename, lineno, indent,
                     margin_indent, margin,
                     truncation, line)

proc Py_DisplaySourceLine*(f; filename: PyObject, lineno, indent: int;
                  margin_indent; margin;
                  truncation: var int, line: var PyStrObject): PyBaseErrorObject =
  ## overload: accept filename as PyObject (unicode) and delegate to string variant
  if filename.isNil:
    return
  assert filename.ofPyStrObject
  let fname = PyStrObject(filename)
  return display_source_lineNotNil(f, fname, lineno, indent,
                     margin_indent, margin,
                     truncation, line)

proc print_error_location_carets(toffset: int, start_offset, end_offset,
                            right_start_offset, left_end_offset: int,
                            primary: cstring, secondary: cstring): string =
    let special_chars = (left_end_offset != -1 or right_start_offset != -1)
    var line: string 
    
    for offset in toffset+1 .. end_offset:
        let str = if offset <= start_offset:
          cstring" "
        elif (special_chars and left_end_offset < offset and offset <= right_start_offset):
          secondary
        else:
          primary
        line.add str
    line

proc Py_DisplaySourceLine*(f; filename: PyStrObject, lineno, indent: int;
                  margin_indent; margin;
                  truncation: var int, line: var PyStrObject): PyBaseErrorObject =
  ## `_Py_DisplaySourceLine`
  return display_source_line(f, filename, lineno, indent,
                     margin_indent, margin,
                     truncation, line)

proc byte_offset_to_character_offset(source_line: PyStrObject, byte_offset: int): int =
  ## `_PyPegen_byte_offset_to_character_offset`
  if source_line.isAscii:
    return byte_offset

  var j = 0
  for i, c in source_line.str.unicodeStr:
    j.inc c.size
    if j >= byte_offset:
      return i
  return source_line.len

#[
/* AST based Traceback Specialization
 *
 * When displaying a new traceback line, for certain syntactical constructs
 * (e.g a subscript, an arithmetic operation) we try to create a representation
 * that separates the primary source of error from the rest.
 *
 * Example specialization of BinOp nodes:
 *  Traceback (most recent call last):
 *    File "/home/isidentical/cpython/cpython/t.py", line 10, in <module>
 *      add_values(1, 2, 'x', 3, 4)
 *    File "/home/isidentical/cpython/cpython/t.py", line 2, in add_values
 *      return a + b + c + d + e
 *             ~~~~~~^~~
 *  TypeError: 'NoneType' object is not subscriptable
 */
]#
using segment_str: string
proc extract_anchors_from_expr(segment_str; expr: AsdlExpr,
                 left_anchor, right_anchor: var int,
                 primary_error_char: var cstring, secondary_error_char: var cstring): bool =
  ## returns if successful
  case expr.kind
  of BinOp:
    let b = AstBinOp(expr)
    let left = b.left
    let right = b.right
    var i = left.col_offset.value  #TODO:end_col_offset
    while i < right.col_offset.value:
      if IS_WHITESPACE(segment_str[i]):
        inc i
        continue

      left_anchor = i
      right_anchor = i + 1

      # Check whether this is a two-character operator (e.g. //)
      if i + 1 < right.col_offset.value and not IS_WHITESPACE(segment_str[i + 1]):
        inc right_anchor

      # Keep going if the current char is ')'
      if i + 1 < right.col_offset.value and (segment_str[i] == ')'):
        inc i
        continue


      primary_error_char = cstring"~"
      secondary_error_char = cstring"^"
      break

    return true

  of Subscript:
    let sub = AstSubscript(expr)
    #TODO:end_col_offset
    left_anchor = sub.value.col_offset.value
    right_anchor = left_anchor  # sub.slice.end_col_offset.value + 1
    let str_len = len(segment_str)

    # Move right_anchor and left_anchor forward to the first non-whitespace
    # character that is '[' / ']' respectively (mirrors original C logic).
    while left_anchor < str_len and (IS_WHITESPACE(segment_str[left_anchor]) or segment_str[left_anchor] != '['):
      inc left_anchor
    while right_anchor < str_len and (IS_WHITESPACE(segment_str[right_anchor]) or segment_str[right_anchor] != ']'):
      inc right_anchor
    if right_anchor < str_len:
      inc right_anchor

    primary_error_char = cstring"~"
    secondary_error_char = cstring"^"
    return true

  else:
    return false

proc extract_anchors_from_stmt(segment_str; statement: AsdlStmt,
                 left_anchor: var int, right_anchor: var int,
                 primary_error_char: var cstring, secondary_error_char: var cstring): bool =
  case statement.kind
  of Expr:
    return extract_anchors_from_expr(segment_str, AstExpr(statement).value,
                    left_anchor, right_anchor,
                    primary_error_char, secondary_error_char)
  else:
    return false

proc extract_anchors_from_line(filename: PyStrObject, line: PyStrObject,
                 start_offset, end_offset: int,
                 left_anchor, right_anchor: var int,
                 primary_error_char: var cstring, secondary_error_char: var cstring): bool =
  ## returns if successful
  
  let segment = line.substringUnsafe(start_offset, end_offset)

  let segment_str = $segment.str

  var flags = initPyCompilerFlags()


  var module: Asdlmodl
  let exc = PyParser_ASTFromString(segment_str, filename, Mode.File,
                     flags, module)
  if not exc.isNil:
    return false

  let modu = AstModule(module)
  if len(modu.body) == 1:
    let statement = modu.body[0]
    result = extract_anchors_from_stmt(segment_str, statement,
                  left_anchor, right_anchor,
                  primary_error_char, secondary_error_char)
  else:
    result = false

#done:
  if result:
    # Normalize AST offsets to character offsets and adjust by start_offset.
    assert left_anchor >= 0
    assert right_anchor >= 0
    left_anchor = byte_offset_to_character_offset(segment, left_anchor) + start_offset
    right_anchor = byte_offset_to_character_offset(segment, right_anchor) + start_offset

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
          margin_indent; margin
          ): PyBaseErrorObject{.raises: [].} =
  if filename.isNil or name.isNil: return

  var line: string
  line.add Py_WriteIndentedMargin(margin_indent, margin)

  let
    filenameS = $filename.str
    name = $PyStrObject(name).str
  line.add &"  File \"{filenameS}\", line {lineno}, in {name}"

  retIfExc PyFile_WritelineString(line, f) # , Py_PRINT_RAW)

  var truncation = TRACEBACK_SOURCE_LINE_INDENT
  var source_line: PyStrObject = nil


  result = display_source_line(
          f, filename, lineno, TRACEBACK_SOURCE_LINE_INDENT,
          margin_indent, margin,
          truncation, source_line);
  if not result.isNil or source_line.isNil:
    # ignore errors since we can't report them, can we?
    if ignore_source_errors(result):
      return nil

  let
    code_offset = tb.tb_lasti
    code = frame.code
    source_line_len = source_line.len

  var
    start_line,
     end_line,
     start_col_byte_offset,
     end_col_byte_offset: int

  retIfExc code.addr2location(code_offset, start_line, start_col_byte_offset,
                           end_line, end_col_byte_offset)

  if start_line < 0 or end_line < 0 or start_col_byte_offset < 0 or end_col_byte_offset < 0:
    return

  let
    start_offset = byte_offset_to_character_offset(source_line, start_col_byte_offset)
    end_offset = byte_offset_to_character_offset(source_line, end_col_byte_offset)

  var
    right_start_offset = -1
    left_end_offset = -1
  
  var
    primary_error_char = cstring"^"
    secondary_error_char = primary_error_char
  # end_offset = tb.colNo
  # start_offset = end_offset
  
  #if start_line == end_line
  let suc = extract_anchors_from_line(
      filename, source_line,
      start_offset, end_offset,
      left_end_offset, right_start_offset,
      primary_error_char, secondary_error_char
      )
  discard suc

  # Elide indicators if primary char spans the frame line
  let
    stripped_line_len = source_line_len - truncation - TRACEBACK_SOURCE_LINE_INDENT
    has_secondary_ranges = (left_end_offset != -1 or right_start_offset != -1)
  if end_offset - start_offset == stripped_line_len and not has_secondary_ranges:
    return nil

  line.setLen 0
  line.add Py_WriteIndentedMargin(margin_indent, margin)

  
  secondary_error_char = cstring"~"
  
  line.add print_error_location_carets(truncation, start_offset, end_offset,
                                    right_start_offset, left_end_offset,
                                    primary_error_char, secondary_error_char)
  result = PyFile_WritelineString(line, f)

const TB_RECURSIVE_CUTOFF = 3


proc tb_print_line_repeated(f; cnt: int): PyBaseErrorObject =
    var cnt = cnt
    cnt -= TB_RECURSIVE_CUTOFF
    var line = fmt"[Previous line repeated {cnt} more time"
    if cnt > 1: line.add 's'
    line.add ']'

    result = PyFile_WritelineString(line, f)

proc tb_printinternal(tb: PyTracebackObject, f; limit: int;
    margin_indent; margin;
    ): PyBaseErrorObject{.raises: [].} =
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
                        frame, code.codeName, margin_indent, margin
                        )
      #TODO:PyErr_CheckSignals
      when declared(PyErr_CheckSignals):
        retIfExc PyErr_CheckSignals()  #TODO:signal

    tb = tb.tb_next_may_nil

  if cnt > TB_RECURSIVE_CUTOFF:
    retIfExc tb_print_line_repeated(f, cnt)

const PyTraceBack_LIMIT = 1000

proc PyTraceBack_Print_Indented_with_noNL_header*(
    v: PyTracebackObject,
    indent: int, margin; header_margin: cstring,
    header: cstring,
    f: PyObject): PyBaseErrorObject{.raises: [].} =
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

  outs.add Py_WriteIndentedMargin(indent, header_margin)

  outs.add header

  retIfExc PyFile_WritelineString(outs, f)

  retIfExc tb_printinternal(v, f, limit, indent, margin)

const
  EXCEPTION_TB_HEADER_noNL* = "Traceback (most recent call last):"  #XXX: like CPython ERROR_TB_HEADER but no newline
  #EXCEPTION_GROUP_TB_HEADER_noNL* = "Exception Group Traceback (most recent call last):"  #XXX: like CPython ERROR_GROUP_TB_HEADER but no newline

proc PyTraceBack_Print_with_noNL_header*(
    v: PyTracebackObject,
    header: cstring,
    f: PyObject): PyBaseErrorObject{.raises: [].} =
  ## `_PyTraceBack_Print`
  const
    indent = 0
    margin = cstring nil
    header_margin = cstring nil
    header = cstring EXCEPTION_TB_HEADER_noNL
  return PyTraceBack_Print_Indented_with_noNL_header(
    v, indent, margin, header_margin, header, f)

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
