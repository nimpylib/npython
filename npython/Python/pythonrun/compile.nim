

import std/strformat
import ../../Include/cpython/compile as compile_h
import ../../Objects/[pyobjectBase,
  stringobjectImpl, exceptions,
  byteobjects,
]
import ../../Parser/[
  lexerTypes, apis,
]
import ../../Python/[asdl, compile]

export lexerTypes, compile_h, PyObject, stringobjectImpl


proc Py_SourceAsString*(cmd: PyObject, funcname, what: string, cf: PyCompilerFlags, cmd_copy: var PyObject; res: var string): PyBaseErrorObject =
  ## `_Py_SourceAsString`
  cmd_copy = nil
  res = if cmd.ofPyStrObject:
    cf.flags = cf.flags | PyCF.IGNORE_COOKIE
    PyStrObject(cmd).asUTF8
  elif cmd.ofPyBytesObject:
    PyBytesObject(cmd).asString
  elif cmd.ofPyByteArrayObject:
    PyByteArrayObject(cmd).asString
  else:
    #TODO:buffer
    return newTypeError newPyStr fmt"{funcname}() arg 1 must be a {what} object"
  if '\0' in res:
    return newSyntaxError newPyAscii"source code string cannot contain null bytes"


proc Py_CompileStringObject*(str: string, filename: PyStrObject, mode: Mode; flags=initPyCompilerFlags(), optimize = -1): PyObject =
  var modu: Asdlmodl

  retIfExc PyParser_ASTFromString(str, filename, mode, flags, modu)
  if not flags.isNil and ((flags.flags.cint and PyCF.ONLY_AST.cint) == PyCF.ONLY_AST.cint):
    # unoptiomized AST
    #let syntax_check_only = flags.flags & PyCF.OPTIMIZED_AST
    result = newNotImplementedError newPyAscii"TODO:ast not impl"
    #result = PyAST_mod2obj modu
    return
  compile(modu, filename, flags, optimize)

