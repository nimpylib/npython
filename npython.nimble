from "npython/versionInfo" import Version

from "npython/Modules/getbuildinfo" import BuildInfoCacheFile, genBuildCacheContent
before install:
  writeFile "npython/Modules/" & BuildInfoCacheFile, genBuildCacheContent()
from "npython/builtinModules/private/skipHandleUtil" import skipHandled
import std/macros; macro asgnVer = quote do: version = `Version`
asgnVer()  # declarative parser of nimble requires version to be literals
#version       = libver.Version
# since nimble@v0.16.4

author        = "Weitang Li (liwt),  lit (litlighilit)"
description   = "Python interpreter implemented in Nim, supporting JS backends"
license       = "MIT"
srcDir        = "."
installExt   = @["nim", "nims"]
installFiles  = @["LICENSE", "npython/Parser/Grammar",
  "npython/builtinModules/private/skipJs.txt"]
skipDirs = @["tests"]
binDir        = "bin"

let srcName = "npython"
namedBin[srcName] = "npython"

requires  "nim > 2.0.8" # 2.0.8 will error: `/pyobjectBase.nim(342, 16) Error: undeclared field: 'pyType=' for type pyobjectBase.PyObject`
when declared(feature):  # nimble v0.18+
  feature "playground":
    requires "karax"

var pylibPre = "https://github.com/nimpylib"
let envVal = getEnv("NIMPYLIB_PKGS_BARE_PREFIX")
if envVal != "": pylibPre = ""
elif pylibPre[^1] != '/':
  pylibPre.add '/'
template pylib(x, ver) =
  requires pylibPre & x & ver

pylib "libffi", "#head"
pylib "intobject", " ^= 0.1.4"
pylib "pysimperr", " ^= 0.1.0"
pylib "pyrepr", " ^= 0.1.1"
pylib "jscompat", " ^= 0.1.6"
pylib "nimpatch", " ^= 0.1.1"
pylib "translateEscape", " ^= 0.1.0"
pylib "handy_sugars", " ^= 0.1.0"
pylib "unicode_case", " ^= 0.1.0"
pylib "unicode_space_decimal", " ^= 0.1.0"
pylib "py_locale_utf8_encoding", " ^= 0.1.0"
pylib "pystrbytes_decl", " ^= 0.1.0"
pylib "pyio_abc", " ^= 0.1.0"
pylib "pytime_utils", " ^= 0.1.0"
pylib "float_utils", " ^= 0.1.1"
pylib "pycomplex", " ^= 0.1.0"
pylib "pystrutils", " ^= 0.1.0"
pylib "since_version", " ^= 0.1.0"
pylib "intflags", " ^= 0.1.0"

pylib "posixos", " ^= 0.1.0"
pylib "pymath", " ^= 0.1.0"

# copied from nimpylib.nimble
#   at 43378424222610f8ce4a10593bd719691fbb634b
func getArgs(taskName: string): seq[string] =
  ## cmdargs: 1 2 3 4 5 -> 1 4 3 2 5
  var rargs: seq[string]
  let argn = paramCount()
  for i in countdown(argn, 0):
    let arg = paramStr i
    if arg == taskName:
      break
    rargs.add arg
  if rargs.len > 1:
    swap rargs[^1], rargs[0] # the file must be the last, others' order don't matter
  return rargs

template mytask(name: untyped, taskDesc: string, body){.dirty.} =
  task name, taskDesc:
    let taskName = astToStr(name)
    body

template taskWithArgs(name, taskDesc, body){.dirty.} =
  mytask name, taskDesc:
    var args = getArgs taskName
    body

import std/os
let binPathWithoutExt = absolutePath(binDir / namedBin[srcName])

proc pytest(pyExe: string, i: string) =
  echo "testing " & i
  exec pyExe & ' ' & i
proc testCwd(pyExe: string) =
  for i in listFiles ".": pyExe.pytest i
proc testInDirDepth1(pyExe: string, args: openArray[string]) =
  let subTest =
    if args.len == 0: "asserts"
    else: args[0]
  withDir "tests/" & subTest:
    pyExe.testCwd

proc testLibs(pyExe: string, args: openArray[string], js: static[bool] = false) =
  let dest = "tests/Lib"
  template check(i; body) =
    let last = i.lastPathPart
    if not last.startsWith"test_": continue
    let moduName = last[5..^1]
    when js:
      skipHandled moduName: body
    else:
      body
  for testFile in listFiles dest:
    check testFile:
      pyExe.pytest testFile
  for testDir in listDirs dest:
    check testDir:
      echo "==Entering ", testDir
      withDir testDir:
        pyExe.testCwd

proc testNoLib(pre, pyExe, pyExeToCheckExists: string, args: openArray[string], js: static[bool] = false) =
  if not fileExists pyExeToCheckExists:
    raise newException(OSError, "please firstly run `nimble " & pre & "`")
  testInDirDepth1 pyExe, args

taskWithArgs testPyLib, "lib test, assuming after build":
  let pyExe = binPathWithoutExt.toExe
  testLibs pyExe, args
taskWithArgs test, "test, assuming after build":
  let pyExe = binPathWithoutExt.toExe
  testNoLib "build", pyExe, pyExe, args
  testLibs pyExe, args, js=false

taskWithArgs testNodeJs, "test nodejs backend, assuming after build":
  let
    pyExeFile = binPathWithoutExt & ".js"
    pyExe = "node " & pyExeFile
  testNoLib "buildJs", pyExe, pyExeFile, args
  testLibs pyExe, args, js=true

taskWithArgs testJsLib, "test lib for js, assuming after build":
  let
    pyExeFile = binPathWithoutExt & ".lib.js"
    pyExe = "node "
  testNoLib "buildJsLib", pyExe, pyExeFile, @["js/lib"] & args

using args: openArray[string]
proc selfExecWithSrcAdd(cmd: string; args) =
  selfExec cmd & " --hints:off --warnings:off" & ' ' &
    args.quoteShellCommand & ' '& srcDir & '/' & srcName
proc selfExecBuildWithSrcAdd(cmd, outfile: string; args) =
  selfExecWithSrcAdd(cmd & " -o:" & outfile, args)

taskWithArgs buildDbg, "debug build, output product will be appended with a suffix `_d`":
  selfExecBuildWithSrcAdd "c -g", (binPathWithoutExt & "_d").toExe, args

template buildLibImpl(cmd, doItForBuildTargetName) {.dirty.} =
  let it = namedBin[srcName]
  selfExecBuildWithSrcAdd cmd, (binDir / doItForBuildTargetName), args

taskWithArgs buildJsLib, "build js non-native library(es6 module)":
  buildLibImpl "js --app:lib -d:jspure", it & ".lib.js"

taskWithArgs buildLib, "build shared library":
  buildLibImpl "c --app:lib --tlsEmulation:on", it.toDll

#taskRequires "buildWasm", "wasm_backend ^= 0.1.2"
taskWithArgs buildWasm, "build .wasm(wasi) executable":
  pylib "wasm_backend", " ^= 0.1.2"
  let res = gorgeEx("nim-wasm-build-flags " & NimVersion, cache=NimVersion)
  if res.exitCode != 0:
    quit res.output
  let cmd = "c " & res.output
  selfExecBuildWithSrcAdd cmd,
    binPathWithoutExt & ".wasm", args

taskWithArgs buildJs, "build JS. supported backends: " &
    "-d:nodejs|-d:deno|-d:jsAlert":
  selfExecBuildWithSrcAdd "js", binPathWithoutExt & ".js", args

taskRequires "buildKarax", "karax"
taskWithArgs buildKarax, "build html page with karax":
  selfExecWithSrcAdd "r --hints:off -d:release Tools/mykarun -d:karax " & " --appName=" & namedBin[srcName],
    args
