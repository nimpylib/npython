
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
  compat,
]


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
  registerBltinFunction("print", builtinPrint)
