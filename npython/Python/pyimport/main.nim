

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
import std/os
import std/strutils
import ../../Utils/compat_io_os
import ../../Objects/stringobject/strformat
import ../../builtinModules/index
import ./utils

let
  mnamekey = newPyAscii"__name__"
  mpathkey = newPyAscii"__file__"
  mpackagekey = newPyAscii"__package__"
  mpathlistkey = newPyAscii"__path__"

type ModuleKind = enum
  mkNotFound,
  mkSource,
  mkPackage,
  mkNamespace

type ModuleLocation = object
  filepath: string
  case kind: ModuleKind
  of mkSource, mkNotFound: discard
  of mkPackage:
    packageDir: string
  of mkNamespace:
    namespacePaths: PyListObject

proc init(m: PyModuleObject, filepath: string) =
  let d = m.getDict
  d[mpathkey] = newPyStr filepath

proc splitModuleName(sname: string): tuple[parentName, childName: string] =
  let dotIdx = sname.rfind('.')
  if dotIdx < 0:
    result.childName = sname
  else:
    result.parentName = sname[0..<dotIdx]
    result.childName = sname[dotIdx + 1..^1]

proc findModuleOnPath(childName: string; searchPaths: PyListObject): ModuleLocation =
  let namespacePaths = newPyList()
  for basePathObj in searchPaths:
    let basePath = $basePathObj
    let packageDir = joinPath(basePath, childName)
    let initPath = joinPath(packageDir, "__init__.py")
    if initPath.fileExistsCompat:
      return ModuleLocation(kind: mkPackage, filepath: initPath, packageDir: packageDir)

    let modulePath = joinPath(basePath, childName).addFileExt("py")
    if modulePath.fileExistsCompat:
      return ModuleLocation(kind: mkSource, filepath: modulePath)

    if packageDir.dirExistsCompat:
      namespacePaths.add newPyStr packageDir

  if namespacePaths.len > 0:
    return ModuleLocation(kind: mkNamespace, namespacePaths: namespacePaths)

  ModuleLocation(kind: mkNotFound)

proc searchPathsFor(parent: PyModuleObject; paths: var PyListObject): bool =
  if parent.isNil:
    paths = sys.path
    return true

  let pathObj = parent.getDict.getOptionalItem(mpathlistkey)
  if pathObj.isNil or not pathObj.ofPyListObject:
    return false

  paths = PyListObject(pathObj)
  true

proc packageNameFor(name: PyStrObject, parentName: string; location: ModuleLocation): PyStrObject =
  case location.kind
  of mkPackage, mkNamespace:
    name
  else:
    newPyStr parentName

proc initGlobals(name: PyStrObject; location: ModuleLocation;
    parentName: string): PyDictObject =
  result = newPyDict()
  result[mnamekey] = name
  result[mpackagekey] = packageNameFor(name, parentName, location)
  case location.kind
  of mkPackage:
    result[mpathkey] = newPyStr location.filepath
    let s: PyStrObject = newPyStr location.packageDir
    result[mpathlistkey] = newPyList([PyObject s])
  of mkSource:
    result[mpathkey] = newPyStr location.filepath
  of mkNamespace:
    result[mpathlistkey] = location.namespacePaths
  of mkNotFound:
    discard

proc bindChild(parent: PyModuleObject; childName: string; child: PyObject) =
  if parent.isNil: return
  parent.getDict[newPyStr childName] = child

type Evaluator = object
  evalFrame: proc (f: PyFrameObject): PyObject {.raises: [].}
template newEvaluator*(f): Evaluator = Evaluator(evalFrame: f)
proc newModuleNotFoundErrorOfName*(name: PyStrObject): PyBaseErrorObject =
    let msg = PyStrFmt&"No module named {name:R}"
    let exc = newModuleNotFoundError msg
    exc.name = name
    exc.msg = msg
    exc

proc pyImport*(rt: Evaluator; name: PyStrObject): PyObject{.raises: [].} =
  let sname = $name
  withBuiltinModule sname, value:
    let modu = value[]()
    sys.modules[name] = modu
    return modu

  let (parentName, childName) = splitModuleName(sname)
  var parentModule: PyModuleObject
  if parentName.len > 0:
    let parent = rt.pyImport(newPyStr parentName)
    retIfExc parent
    let module = sys.modules.getOptionalItem(name)
    if not module.isNil:
      return module
    parentModule = PyModuleObject parent

  var alreadyIn: bool
  let module = import_add_module(name, alreadyIn)

  if alreadyIn:
    return module

  var searchPaths: PyListObject
  if not searchPathsFor(parentModule, searchPaths):
    return newModuleNotFoundErrorOfName name
  
  let location = findModuleOnPath(childName, searchPaths)
  if location.kind == mkNotFound:
    return newModuleNotFoundErrorOfName name

  let globals = initGlobals(name, location, parentName)
  module.dict = globals
  bindChild(parentModule, childName, module)

  if location.kind == mkNamespace:
    return module

  let input = try:
    readFileCompat(location.filepath)
  except IOError as e:
    #TODO:io maybe newIOError?
    return newImportError(newPyAscii"Import Failed due to IOError " & newPyAscii $e.msg)
  let compileRes = compile(input, location.filepath)
  retIfExc compileRes

  let co = PyCodeObject(compileRes)

  when defined(debug):
    echo co
  let fun = newPyFunc(name, co, globals)
  let f = newPyFrame(fun)
  let retObj = rt.evalFrame(f)
  retIfExc retObj

  module.init location.filepath
  module
