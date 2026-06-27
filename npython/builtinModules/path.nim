## ntpath & posixpath

import std/macros
import ./private/[utils, gen, dispatch,]
import ./private/fspathUtils/[fspath, consts,]
imp Python, getargs/tovals
imp Python, getargs/topys
import pkg/handy_sugars/trans_imp
import pkg/posixos/path
import ./path/topyvals

impObjects [
  pyobject,
  exceptions,
  bltcommon, 
  moduleobjectImpl,
  stringobject,
  byteobjects,
]
genModule path, moduleName=(
    when defined(windows): "nt"
    else: "posix"
  ) & "path"

genClinicGen path
template genGenX(X; cb) {.dirty.} =
  macro `gen X`(ls: static[openArray[string]]) =
    result = newStmtList()
    for i in ls:
      result.add newCall(cb, ident i)
genGenX Funcs, "clinicGenpath"

template gen_const(nam) {.dirty.} =
  genProperty pathModule, astToStr(nam), nam: newPyAscii(nam)
genGenX Consts, "gen_const"

clinicGenpathSig basename(p: PathLike)
clinicGenpathSig getsize(p: PathLike), [OSError]
clinicGenpath samefile, [OSError, ValueError]

template genGetXTime(getmtime) {.dirty.} =
  clinicGenpathSig getmtime(p: PathLike), [OSError]
genGetXTime getmtime
genGetXTime getatime
genGetXTime getctime

template fspathAs(x: untyped{atom}; funcname: string; Str, Bytes): untyped =
  ## genericpath._check_arg_types
  var res: PyObject
  retIfExc fspath(x, res)
  if res.`ofPy Bytes Object`:
    return cannotMixPathLikeError()
  if not res.`ofPy Str Object`:
    return shouldBePathLike3Error(res, funcname)
  `Py Str Object` res

proc join*(a: PyObject, args: varargs[PyObject]): PyObject =
  var res: PyObject
  retIfExc fspath(a, res)
  var acc: string
  template loop(Str, Bytes) =
    for i in args:
      acc = join(acc, $i.fspathAs("join", Str, Bytes))
    result = `newPy Str` acc
  if res.`ofPy Bytes Object`:
    acc = PyBytesObject(res).asString
    loop Bytes, Str
  else:
    acc = PyStrObject(res).asUTF8
    loop Str, Bytes
implpathModuleMethod join(a, *p): join(a, p)

const OsPathStrConsts* = [
  "curdir", "pardir", "sep", "pathsep", "defpath", "extsep", "altsep",
  "devnull"]
genConsts OsPathStrConsts

const duallFuncs = [
   "normcase",
   "isabs",
   #@above
   #"join",
   "splitdrive",
   #"splitroot",
   "split","splitext",
   #@above: ambig against macros.basename
   #"basename",
   "dirname",
   #"commonprefix",
   #@above: ambig against macros.getSize
   #"getsize",
   #@above: ambig against ??? iff js (idk what the hell)
   #"getmtime", "getatime","getctime",
   "islink",
   #"exists","lexists",
   "isdir","isfile",
   #"ismount",
   "expanduser",
   #"expandvars",
   "normpath","abspath",
   #@above
   #"samefile",
   #"sameopenfile",
   #TODO:stat
   #"samestat",
   #@above:consts:
   #"curdir","pardir","sep","pathsep","defpath","altsep","extsep", devnull",
   #"realpath",
   #"supports_unicode_filenames",
   #@getargs
   #"relpath",
   #"commonpath","isjunction","isdevdrive",
   #"ALL_BUT_LAST","ALLOW_MISSING"
]
genFuncs duallFuncs
