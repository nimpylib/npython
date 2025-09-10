

import ../[
  sysmodule_instance,
  neval_frame,
  compile,
]
import ../../Objects/[pyobject,
  stringobject,
  dictobject, listobject,
  codeobject, funcobject, frameobject,
  exceptionsImpl, moduleobjectImpl,
  ]
import ../../Objects/stringobject/strformat

let
  mnamekey = newPyAscii"__name__"
  mpathkey = newPyAscii"__file__"

proc init(m: PyModuleObject, filepath: string) =
  let d = m.getDict
  d[mpathkey] = newPyStr filepath
import ../../Utils/compat_io_os
import std/os

type Evaluator = object
  evalFrame: proc (f: PyFrameObject): PyObject {.raises: [].}
template newEvaluator*(f): Evaluator = Evaluator(evalFrame: f)

proc pyImport*(rt: Evaluator; name: PyStrObject): PyObject{.raises: [].} =
  let modu = sys.modules.getOptionalItem(name)
  if not modu.isNil:
    return modu

  var filepath: string
  let sname = $name
  for path in sys.path:
    let p = joinPath($path, sname).addFileExt("py")
    if p.fileExistsCompat:
      filepath = p
  
  if filepath == "":
    let msg = newPyStr&"No module named {name:R}"
    retIfExc msg
    let exc = newModuleNotFoundError(PyStrObject msg)
    exc.name = name
    exc.msg = msg
    return exc
  let input = try:
    readFileCompat(filepath)
  except IOError as e:
    #TODO:io maybe newIOError?
    return newImportError(newPyAscii"Import Failed due to IOError " & newPyAscii $e.msg)
  let compileRes = compile(input, filepath)
  if compileRes.isThrownException:
    return compileRes

  let co = PyCodeObject(compileRes)

  when defined(debug):
    echo co
  let fun = newPyFunc(name, co, newPyDict())
  let f = newPyFrame(fun)
  # __name__ = '__main__'
  f.globals[mnamekey] = name
  let retObj = rt.evalFrame(f)
  if retObj.isThrownException:
    return retObj
  let module = newPyModule(name)
  module.dict = f.globals
  module.init filepath
  let ret = sys.modules.setItem(name, module)
  assert ret.isNil
  module
