

import ../../Objects/[
  stringobject/codec,
  noneobject,
  codeobject, cellobject,
  dictobject,
  tupleobjectImpl,
  exceptions,
]
import ../../Objects/abstract/[helpers, mapping]
import ../pythonrun/compile
import ../getargs/[
  dispatch, paramsMeta,
]
import ../[
  neval_frame, neval, pythonrun,
]
import ../sysmodule/audit
import ../ceval/[globalslocals, ]

proc compile*(
  source: PyObject, filename{.convertVia(PyUnicode_FSDecoder).}: PyStrObject,
    mode: string, flags: int = 0,
    dont_inherit=false, optimize = -1,
    feature_version{.startKwOnly, AsPyParam"_feature_version".} = -1): PyObject{.bltin_clinicGen.} =
  #const start = Mode.toSeq
  var cf = initPyCompilerFlags()
  let flags = typeof(cf.flags)(flags)
  cf.flags = flags | PyCF.SOURCE_IS_UTF8
  if feature_version >= 0 and (flags & PyCF.ONLY_AST):
    cf.feature_version = feature_version

  if optimize < -1 or optimize > 2:
    return newValueError newPyAscii"compile(): invalid optimize value"

  var emode: Mode
  if not parseModeEnum($mode, emode):
    #TODO:_ast "compile() mode 'func_type' requires flag PyCF_ONLY_AST"
    return newValueError newPyAscii("compile() mode must be 'exec', 'eval' or 'single'")

  #let is_ast = source.ofPyASTObject  #TODO:_ast
  var source_copy: PyObject
  var str: string
  retIfExc Py_SourceAsString(source, "compile", "string, bytes or AST", cf, source_copy, str)

  Py_CompileStringObject(str, filename, emode, cf, optimize)

proc exec*(
  source: PyObject, globals: PyObject = pyNone, locals: PyObject = pyNone,
    closure: PyObject = nil): PyObject{.bltin_clinicGen.} =
  var globals = globals
  var fromframe = false
  if globals.isPyNone:
    if not PyEval_GetFrame().isNil:
      fromframe = true
      globals = PyEval_GetGlobals()
      assert not globals.isNil
    else:
      globals = PyEval_GetGlobalsFromRunningMain()
      if globals.isNil:
        return newSystemError newPyAscii "globals and locals cannot be NULL"
  
  var locals = locals
  if locals.isPyNone:
    if fromframe:
      locals = PyEval_GetFrameLocals()
      retIfExc locals
    else:
      locals = globals
  
  if not globals.ofPyDictObject:
    return type_errorn("exec() globals must be a dict, not $#", globals)
  if not locals.ofPyMapping:
    return type_errorn("exec() locals must be a mapping or None, not $#", locals)

  locals = nil
  TODO_locals locals

  let dglobals = PyDictObject globals
  retIfExc PyEval_EnsureBuiltins(dglobals)

  var closure = closure
  if closure.isPyNone:
    closure = nil
  
  if source.ofPyCodeObject:
    let co = PyCodeObject source
    let num_free = co.freeVars.len
    if num_free == 0:
      if not closure.isNil:
        return type_error "cannot use a closure with this code object"
    else:
      var tup: PyTupleObject
      var closure_is_ok = not closure.isNil and closure.ofPyTupleObject and (
        tup = PyTupleObject(closure); tup.len == num_free)
      if closure_is_ok:
        for i in 0 ..< num_free:
          let cell = tup[i]
          if not cell.ofPyCellObject:
            closure_is_ok = false
            break
      if not closure_is_ok:
        return type_error("code object requires a closure of exactly length " & $num_free)

    retIfExc audit("exec", source)

    result = if closure.isNil:
      evalCode(co, dglobals, locals)
    else:
      evalCode(co, dglobals, locals, closure)
  else:
    if not closure.isNil:
      return type_error "closure can only be used when source is a code object"

    var cf = initPyCompilerFlags()
    cf.flags = typeof(cf.flags) PyCF.SOURCE_IS_UTF8
    var source_copy: PyObject
    var str: string
    retIfExc Py_SourceAsString(source, "exec", "string, bytes or AST", cf, source_copy, str)
    result = if PyEval_MergeCompilerFlags(cf):
      PyRun_StringFlags(str, Mode.File, dglobals, locals, cf)
    else:
      PyRun_String(str, Mode.File, dglobals, locals)
  retIfExc result
  return pyNone

template reg(f) =
  registerBltinFunction astToStr(f), `builtin f`
template register_compile_eval_exec* =
  reg compile
  reg exec
