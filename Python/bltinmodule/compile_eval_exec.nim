
from std/strutils import strip
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

template init_globals_locals_ensure_bltin(no_globals_err,
      globals_invalid, locals_invalid
    ){.dirty.} =

  var globals = globals
  var fromframe = false
  if globals.isPyNone:
    if not PyEval_GetFrame().isNil:
      fromframe = true
      globals = PyEval_GetGlobals()
      assert not globals.isNil
    else:
      globals = PyEval_GetGlobalsFromRunningMain()
      if globals.isNil or globals.isThrownException:
        return newSystemError newPyAscii no_globals_err
  
  var locals = locals
  if locals.isPyNone:
    if fromframe:
      locals = PyEval_GetFrameLocals()
      retIfExc locals
    else:
      locals = globals
  
  if not globals.ofPyDictObject:
    return type_error globals_invalid
  if not locals.ofPyMapping:
    return type_error locals_invalid

  locals = nil
  TODO_locals locals

  let dglobals = PyDictObject globals
  retIfExc PyEval_EnsureBuiltins(dglobals)

template asStringAndInitCf(source, funName){.dirty.} =
  var cf = initPyCompilerFlags()
  cf.flags = typeof(cf.flags) PyCF.SOURCE_IS_UTF8
  var source_copy: PyObject
  var str: string
  retIfExc Py_SourceAsString(source, funName, "string, bytes or AST", cf, source_copy, str)

proc eval*(
    source: PyObject, globals: PyObject = pyNone, locals: PyObject = pyNone,
  ): PyObject{.bltin_clinicGen.} =
  var globalsIsDict = globals.ofPyDictObject
  # if not globals.isPyNone and not (globalsIsDict = globals.ofPyDictObject; globalsIsDict):
  #   return type_error(
  #       )
  # if not locals.isPyNone and not locals.ofPyMapping:
  #   return type_error 

  init_globals_locals_ensure_bltin(
    "eval must be given globals and locals when called without a frame",
      if globalsIsDict: "globals must be a real dict; try eval(expr, {}, mapping)"
      else: "globals must be a dict"
      ,
    "locals must be a mapping"
  )
  if source.ofPyCodeObject:
    let co = PyCodeObject source
    retIfExc audit("exec", source)
    if co.freeVars.len > 0:
      return type_error "code object passed to eval() may not have free variables"

    result = evalCode(co, dglobals, locals)
  else:
    asStringAndInitCf source, "eval"

    str = str.strip(chars={' ', '\t'}, trailing=false)

    discard PyEval_MergeCompilerFlags(cf)

    return PyRun_StringFlags(str, Mode.Eval, dglobals, locals, cf)


proc exec*(
  source: PyObject, globals: PyObject = pyNone, locals: PyObject = pyNone,
    closure: PyObject = nil): PyObject{.bltin_clinicGen.} =
  
  init_globals_locals_ensure_bltin(
    "globals and locals cannot be NULL",
    "exec() globals must be a dict, not " & globals.typeName,
    "exec() locals must be a mapping or None, not " & locals.typeName

  )

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

    asStringAndInitCf source, "exec"
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
  reg eval
