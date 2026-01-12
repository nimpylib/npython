
import ../../Objects/[
  pyobject,
  exceptionsImpl,
]
import ../[
  traceback,
]
import ../../Utils/[compat, 
  #utils,
  fileio,
]

import std/strformat
import ../sysmodule/attrs
import ../../Objects/[
  stringobject,
  setobjectAux,
  noneobject,
]
import ../../Include/internal/pycore_ceval_rec
import ../../Include/internal/pycore_global_strings
import ../../Objects/pyobject_apis/[attrs, strings,]
import ../../Objects/typeobject/getters
import ../../Objects/numobjects/intobject

#[
const
  PyErr_MAX_GROUP_WIDTH = 15
  PyErr_MAX_GROUP_DEPTH = 10

template EXC_MARGIN(ctx): untyped = (if ctx.exception_group_depth != 0: cstring"| " else: cstring"")
template EXC_INDENT(ctx): untyped = 2 * ctx.exception_group_depth
]#

type
  exception_print_context = object
    file: PyObject
    exception_group_depth: cint
    need_close: bool
    max_group_width: cint
    max_group_depth: cint
    seen: PySetObject


using
  ctx: exception_print_context
  value: PyBaseExceptionObject
proc print_exception_invalid_type(ctx; value): PyBaseErrorObject =
  let msg = "TypeError: print_exception(): Exception expected for value, " &
        value.typeName & " found"
  PyFile_WritelineString(msg, ctx.file)

proc print_exception_traceback(ctx; value): PyBaseErrorObject =
  let f = ctx.file

  let tb = value.traceback
  if not tb.isNil and not tb.isPyNone:
    let header: cstring = EXCEPTION_TB_HEADER_noNL
    result = PyTraceBack_Print_with_noNL_header(tb, header, f)

proc print_exception_file_and_line(ctx; valueRef: var PyObject): PyBaseErrorObject =
  let f = ctx.file

  var tmp: PyObject = nil
  let res = PyObject_GetOptionalAttr(valueRef, pyId(print_file_and_line), tmp)
  case res
  of Missing: return
  of Error: return PyBaseErrorObject tmp
  of Get: discard

  let v = PyObject_GetAttr(valueRef, pyId filename)
  retIfExc v

  let filename: PyStrObject =
    if v.isPyNone:
      newPyStr(pyId "<string>")
    else:
      if not v.ofPyStrObject:
        return newTypeError newPyAscii"filename must be a string or None"
      PyStrObject v
  
  let lineno = 0

  let filenameS = $filename.str
  let line = &"  File \"{filenameS}\", line {lineno}"

  retIfExc(PyFile_WritelineString(line, f))

proc get_print_exception_message(typ: PyObject; value; line: var string): PyBaseErrorObject =
  ## return the message line: `module.qualname[: str(exc)]`
  # Try to print using a raw object write to the file.
  
  if value.isExceptionOf Memory:
    #[The Python APIs in this function require allocating memory
    for various objects. If we're out of memory, we can't do that,]#
    return PyBaseErrorObject value

  assert typ.ofPyExceptionClass

  var modulename = PyObject_GetAttr(typ, pyDUId(module))
  if modulename.isNil or not modulename.ofPyStrObject:
    #retIfExc(PyFile_WriteString("<unknown>.", f))
    line.add "<unknown>."

  else:
    let modulenameStr = PyStrObject(modulename)
    #if not modulenameStr.eqAscii"builtins" and not modulenameStr.eqAscii"__main__":
    if modulenameStr != pyId(builtins) and modulenameStr != pyDUId(main):
      line.add $modulenameStr.str
      line.add '.'

  var qualname = cast[PyTypeObject](typ).getQualName
  if qualname.isNil or not qualname.ofPyStrObject:
    line.add "<unknown>"
  else:
    line.add $PyStrObject(qualname).str

  if value.isPyNone:
    return nil

  let s = PyObject_Str(value)
  if s.isThrownException:
    line.add ": <exception str() failed>"
  else:
    #[only print colon if the str() of the
      object is not the empty string]#
    if not s.ofPyStrObject or PyStrObject(s).len != 0:
      line.add ": "
    line.add $PyStrObject(s).str


proc print_exception(ctx; value): PyBaseErrorObject{.raises: [].} =
  var f = ctx.file
  if not value.ofPyExceptionInstance():
    return print_exception_invalid_type(ctx, value)

  flushFile(stdout)

  retIfExc(print_exception_traceback(ctx, value))

  # grab the type now because value can change below
  let typ = cast[PyObject](value.pyType)

  var valueRef: PyObject = value
  retIfExc(print_exception_file_and_line(ctx, valueRef))
  var line: string
  retIfExc(get_print_exception_message(typ, value, line))
  retIfExc(PyFile_WritelineString(line, f))

const
  cause_message* = "The above exception was the direct cause " &
                   "of the following exception:\n"
  context_message* = "During handling of the above exception, " &
                     "another exception occurred:\n"

proc print_exception_recursive(ctx; value): PyBaseErrorObject{. raises: [].}

proc print_chained(ctx; value;
                    message: cstring; tag: cstring): PyBaseErrorObject =
  let f = ctx.file
  withNoRecusiveCallOrRetE(" in print_chained"):
    result = print_exception_recursive(ctx, value)
  retIfExc result

  retIfExc(PyFile_WritelineString("", f))
  retIfExc(PyFile_WritelineString(message, f))


proc print_exception_seen_lookup(ctx; value): bool =
  ##[
  Return true if value is in seen or there was a lookup error.
  Return false if lookup succeeded and the item was not found.
  We suppress errors because this makes us err on the side of
  under-printing which is better than over-printing irregular
  exceptions (e.g., unhashable ones).
  ]##
  var check_id = newPyIntFromPtr(value)
  if check_id.isThrownException:
    return true

  let in_seen = check_id in ctx.seen
  #Py_DECREF(check_id) # safe removal: if project still defines this as noop; otherwise remove
  if in_seen:
    return true


proc print_exception_cause_and_context(ctx; value): PyBaseErrorObject =
  var value_id = newPyIntFromPtr(value)
  if value_id.isThrownException:
    #Py_XDECREF(value_id) # safe removal or noop in GC world
    return
  
  ctx.seen.incl value_id
  if not value.ofPyExceptionInstance():
    return nil

  when compiles(value.cause):
    #TODO:exception.cause
    var cause = value.cause
    if not cause.isNil:
      if not print_exception_seen_lookup(ctx, cause):
        retIfExc(print_chained(ctx, cause, cause_message, "cause"))
      return

  if value.suppress_context:
    return

  var context = value.context
  if not context.isNil:
    if not print_exception_seen_lookup(ctx, context):
      retIfExc(print_chained(ctx, context, context_message, "context"))
    return

proc print_exception_recursive(ctx; value): PyBaseErrorObject{. raises: [].} =
  withNoRecusiveCallOrRetE(" in print_exception_recursive"):
    if ctx.seen != nil:
      # Exception chaining
      retIfExc print_exception_cause_and_context(ctx, value)  
    retIfExc print_exception(ctx, value)


using file: PyObject
proc private_PyErr_Display(file; unused: PyObject; value; tb: PyObject){.raises: [].} =
  ## `_PyErr_Display`
  assert(file != nil and not file.isPyNone)
  if ofPyExceptionInstance(value) and tb != nil and ofPyTraceBackObject(tb):
    let cur_tb = value.privateGetTracebackRef
    if cur_tb.isNil:
      #[ Put the traceback on the exception, otherwise it won't get
           displayed.  See issue cpython/cpython#18776.]#
      value.privateGetTracebackRef = tb

  #TODO:import traceback._print_exception_bltin

  when false:
    var print_exception_fn = PyImport_ImportModuleAttrString("traceback", "_print_exception_bltin")
    if not print_exception_fn.isThrownException and ofPyCallable(print_exception_fn):
      let result = call(print_exception_fn, value)
      if not result.isThrownException:
        return

  # fallback
  when defined(Py_DEBUG):
    if not result.isNil:
      if result.isThrownException:
        PyErr_FormatUnraisable newPyAscii"Exception ignored in the internal traceback machinery"

  var ctx: exception_print_context
  ctx.file = file

  #[ We choose to ignore seen being possibly NULL, and report
  at least the main exception (it could be a MemoryError).]#

  var seen = newPySet()
  if seen.isThrownException:
    seen = nil
  ctx.seen = seen

  # print_exception_recursive returns nil on success, an exception object on failure
  let excObj = print_exception_recursive(ctx, value)
  if not excObj.isNil:
    PyUnstable_Object_Dump(value)
    errEchoCompatNoRaise("lost sys.stderr")

  when declared(PyFile_Flush):
    #TODO:io
    discard PyFile_Flush(file)
  # Silently ignore file.flush() error

proc PyErr_Display*(unused: PyObject; value; tb: PyObject) =
  var file: PyObject = nil
  let exc = PySys_GetOptionalAttr(pyId(stderr), file)

  #TODO:io
  file = newPyInt(2)

  if not exc.isNil:
    PyUnstable_Object_Dump(value)
    errEchoCompatNoRaise("lost sys.stderr")
    PyUnstable_Object_Dump(exc)
    return

  if file == nil:
    PyUnstable_Object_Dump(value)
    errEchoCompatNoRaise("lost sys.stderr")
    return

  if file.isPyNone:
    return

  private_PyErr_Display(file, nil, value, tb)

proc privatePyErr_DisplayException*(file; value) =
  ## `_PyErr_DisplayException`
  privatePyErr_Display(file, nil, value, nil)

proc PyErr_DisplayException*(value) =
  PyErr_Display(nil, value, nil)

#[
proc PyErr_Display*(unused: PyObject#[PyTypeObject]#, value: PyBaseErrorObject; tb: PyObject) {.raises: [].} =
  #TODO:PyErr_Display  after PyObject_Dump, _PyErr_Display
  try:
    value.printTb
  except IOError: discard
  except KeyError as e:
    try: errEchoCompat("Nim: KeyError when PyErr_Display: " & e.msg)
    except IOError: discard

proc PyErr_DisplayException*(exc: PyBaseErrorObject) = PyErr_Display(nil, exc, nil)
]#
