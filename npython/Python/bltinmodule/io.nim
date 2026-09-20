
import ../getargs/[
  dispatch,
  kwargs, optionstr,
]
import ../../Objects/[
  pyobjectBase,
  exceptions,
  exceptions/ioerror,
  noneobject,
  boolobjectImpl,
  stringobject,
  dictobject,
  fileobject/generics,
  pyobject_apis/strings,
  pyobject_apis/attrs,
]
import ../../Include/cpython/pylock
import ../../Include/internal/pycore_global_strings
import ../sysmodule/[
  audit, attrs,
]
import ../../Objects/abstract/call
import ../../Python/call
import pkg/pysimperr/rterr

proc input*(prompt: PyObject=nil): PyObject{.bltin_clinicGen.} =
  template chkOrLost(id) =
    let `id obj` = PySys_GetDataChecked id
    #PySys_GetAttr pyId id  # PySys_GetAttr is responsible to set "lost sys.xxx" msg
    retIfExc `id obj`
  chkOrLost stdin
  chkOrLost stdout
  chkOrLost stderr

  retIfExc audit("builtins.input", if prompt.isNil: pyNone else: prompt)

  var promptstr: PyStrObject
  block readline:
    #template goto_readline_errors = break readline
    if not prompt.isNil:
      let stringpo = PyObject_StrNonNil prompt
      retIfExc stringpo
      #goto_readline_errors
      promptstr = PyStrObject(stringpo)
      if '\0' in promptstr:
        return newValueError newPyAscii"input: prompt string cannot contain null characters"
    else:
      promptstr = newPyAscii()
    retIfExc stdoutObj.callMethod(pyId"write", promptstr)
    retIfExc PyFile_Flush stdoutObj
    return stdinObj.callMethod(newPyAscii"readline")
  # _readline_errors


const NewLine = "\n"

when SingleThread:
  var priRtErr: PyBaseErrorObject
  template withPriLock(body) = body
else:
  var prilock: PyMutex  # also lock for IO
  var priRtErr{.guard: prilock.}: PyBaseErrorObject

  template withPriLock(body) =
    withLock prilock: body

proc printImpl(args: varargs[PyObject],
    sep: string|PyStrObject = " ", endl: string|PyStrObject = NewLine,
    file = pyNoneObj, flush = false
  ) =

  when sep is PyStrObject:
    let sep = $sep.str
  when endl is PyStrObject:
    let endl = $endl.str

  var file = file
  if file.isNil or file.isPyNone:
    file = PySys_GetDataChecked stdout #PySys_GetAttr("stdout");.. Lost
    # CPython: print does nothing if sys.stdout is None
    if file.isPyNone:
      return
  withPriLock:
    template handleExc(eExpr) =
      let e = eExpr
      if e.isThrownException:
        # caller holds the lock already
        priRtErr = PyBaseErrorObject e
        # for opt, we didn't attach info from priRtErr to RuntimeError
        #  which is just a signal
        raise new RuntimeError
    template toStr(obj): PyStrObject =
      let objStr = PyObject_StrNonNil obj
      handleExc(objStr)
      PyStrObject(objStr)

    let f = PyObject_GetAttr(file, pyId"write")
    handleExc f
    if args.len != 0:
      handleExc f.call(args[0].toStr)
      let sepO = newPyStr sep
      for i in 1..<args.len:
        handleExc f.call(sepO)
        handleExc f.call(args[i].toStr)
    handleExc f.call(newPyStr endl)
    if flush:
      handleExc PyFile_Flush file

proc printNoRaise*(args: varargs[PyObject],
    sep: string|PyStrObject = " ", endl: string|PyStrObject = NewLine,
    file = pyNoneObj, flush = false
  ): PyBaseErrorObject =
  ## `print`_ but not raise, just returning the exception
  try: printImpl(args, sep, endl, file, flush)
  except RuntimeError:
    withPriLock:
      result = priRtErr
proc print*(args: varargs[PyObject],
    sep: string|PyStrObject = " ", endl: string|PyStrObject = NewLine,
    file = pyNoneObj, flush = false
  ) =
  let exc = printNoRaise(args, sep, endl, file, flush)
  if not exc.isNil:
    raise newException(RuntimeError, $exc)

proc builtinPrint*(args: openArray[PyObject], kwargs: PyObject): PyObject {. pyCFuncPragma .} =
  let kwargs = PyDictObject kwargs
  #retIfExc PyArg_UnpackKeywordsToAs("print", kwargs, sep, `end`, file, flush)
  retIfExc PyArg_UnpackKeywordsAs("print", kwargs,
    ["sep", "end", "file", "flush"],
    osep, oend, ofile, oflush,
  )
  var
    sep = " "
    endl = NewLine
  retIfExc getOptionalStr("sep", osep, sep)
  retIfExc getOptionalStr("end", oend, endl)
  var flush = false
  if not oflush.isNil:
    retIfExc oflush.PyObject_IsTrue flush
  try:
    printImpl(args, sep, endl, ofile, flush)
    return pyNone
  except IOError as e:
    return newIOError e
  except RuntimeError:
    withPriLock:
      return priRtErr

template register_io* =
  registerBltinFunction("input", builtin_input)
  registerBltinFunction("print", builtinPrint)
