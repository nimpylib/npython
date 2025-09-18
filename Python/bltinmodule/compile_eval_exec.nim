

import ../../Objects/[
  stringobject/codec,
  exceptions,
]
import ../pythonrun/compile
import ../getargs/[
  dispatch, paramsMeta,
]

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

template reg(f) =
  registerBltinFunction astToStr(f), `builtin f`
template register_compile_eval_exec* =
  reg compile
