
import ../getargs/[
  dispatch,
  kwargs, optionstr,
]
import ../../Objects/[
  pyobjectBase,
  exceptions,
  exceptions/ioerror,
  noneobject,
  stringobject,
  dictobject,
  pyobject_apis/strings,
]
import ../../Utils/[
  compat, fileio, utils,
]
import ../sysmodule/[
  audit,
]

proc input*(prompt: PyObject=nil): PyObject{.bltin_clinicGen.} =
  #TODO:sys.stdin
  #TODO:sys.stdout
  #TODO:sys.stderr
  #[
  template chkOrLost(id) =
    let obj = PySys_GetNonNoneAttr pyId id  # PySys_GetNonNoneAttr EXT is responsible to set "lost sys.xxx" msg
    retIfExc obj
  chkOrLost stdin
  chkOrLost stdout
  chkOrLost stderr
  ]#

  retIfExc audit("builtins.input", if prompt.isNil: pyNone else: prompt)

  var promptstr: string
  block readline:
    #template goto_readline_errors = break readline
    if not prompt.isNil:
      let stringpo = PyObject_StrNonNil prompt
      retIfExc stringpo
      #goto_readline_errors
      promptstr = PyStrObject(stringpo).asUTF8  #TODO:sys.stdout,PyUnicode_AsEncodedString
      if '\0' in promptstr:
        return newValueError newPyAscii"input: prompt string cannot contain null characters"
    else:
      promptstr = ""
    let s = try:
      when defined(nodejs):
        when declared(nodeReadLineSync): nodeReadLineSync promptstr
        else: return newNotImplementedError newPyAscii"#TODO:input sync readline not impl in nodejs backend"; ""
      else: readLine(stdin, stdout, promptstr) # readLine handles the case if stdin is not tty
    except EOFError:
      return newEOFError()
    except IOError as e:
      return newIOError e
    except InterruptError:
      return newKeyboardInterrupt()
    result = newPyStr s
    return
  # _readline_errors


const NewLine = "\n"
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
  
  template notImpl(argname, obj) =
    if not obj.isNil and not obj.isPyNone:
      return newNotImplementedError(
        newPyAscii argname & " currently can only be None"
      )
  #TODO:kwargs
  notImpl "file", ofile
  notImpl "flush", oflush

  #TODO:sys.stdout: shall do nothing if missing sys.stdout; else write to it
  const noWrite = not declared(writeStdoutCompat)
  when noWrite:
    var res: string
    template writeStdoutCompat(s) = res.add s
  template toStr(obj): string =
    let objStr = PyObject_StrNonNil obj
    retIfExc(objStr)
    $PyStrObject(objStr).str
  try:
    if args.len != 0:
      writeStdoutCompat args[0].toStr
      if args.len > 1:
        for i in 1..<args.len:
          writeStdoutCompat sep
          writeStdoutCompat args[i].toStr
    when noWrite:
      let stripNL = endl
      if endl == NewLine:
        echoCompat res
      elif endl.len > 1 and endl[^1] == NewLine[0]:
        writeStdoutCompat endl[0..^2]
        echoCompat res
      else:
        return newNotImplementedError(
          newPyAscii"this build target cannot print if `not end.endswith('\n')`"
        )
    else:
      writeStdoutCompat endl
  except IOError as e:
    return newIOError e
  pyNone

template register_io* =
  registerBltinFunction("input", builtin_input)
  registerBltinFunction("print", builtinPrint)
