

import ./[
  sysmodule_instance,
  neval_frame,
  compile,
]
import ../Objects/[pyobject,
  stringobject,
  dictobject,
  codeobject, funcobject, frameobject,
  exceptionsImpl, moduleobjectImpl,
  ]
import ../Objects/numobjects/intobject
import ./coreconfig

let
  mtimekey = newPyAscii"_npython_module_changetime"
  mpathkey = newPyAscii"__file__"

template getmtimeUnraisable(path): untyped =
  try: path.getLastModificationTime except OSError: return

when not defined(js):
  import std/[os, times]
  proc refresh(m: PyModuleObject, filepath: string) =
    let d = m.getDict

    d[mpathkey] = newPyStr filepath

    d[mtimekey] = newPyInt filepath.getmtimeUnraisable.toUnix


proc fresh(m: PyModuleObject): bool =
  let d = m.getDict
  var res: PyObject

  res = d.getOptionalItem(mtimekey)
  if res.isNil:
    # builtin module has no __file__
    #  and doesn't need to refresh
    return true
  let mtime = PyIntObject res

  res = d.getOptionalItem(mpathkey)
  if res.isNil: return
  let path = $PyStrObject(res)

  mtime.toInt64Unsafe == path.getmtimeUnraisable.toUnix

type Evaluator = object
  evalFrame: proc (f: PyFrameObject): PyObject {.raises: [].}
template newEvaluator*(f): Evaluator = Evaluator(evalFrame: f)

proc pyImport*(rt: Evaluator; name: PyStrObject): PyObject{.raises: [].} =
  let modu = sys.modules.getOptionalItem(name)
  if not modu.isNil:
    let m = PyModuleObject modu
    if fresh(m):
      return modu

  when defined(js):
    newRunTimeError(newPyAscii"Can't import in js mode")
  else:
    let filepath = pyConfig.path.joinPath($name.str).addFileExt("py")
    if not filepath.fileExists:
      let fp = newPyStr filePath
      let msg = newPyAscii"File " & fp & newPyAscii" not found"
      let exc = newImportError(msg)
      exc.name = fp
      return exc
    let input = try:
      readFile(filepath)
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
    let retObj = rt.evalFrame(f)
    if retObj.isThrownException:
      return retObj
    let module = newPyModule(name)
    module.dict = f.globals
    module.refresh filepath
    let ret = sys.modules.setItem(name, module)
    assert ret.isNil
    module
