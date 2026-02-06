from "Python/versionInfo" import Version

from "Modules/getbuildinfo" import BuildInfoCacheFile, genBuildCacheContent
before install:
  writeFile "Modules/" & BuildInfoCacheFile, genBuildCacheContent()

import std/macros; macro asgnVer = quote do: version = `Version`
asgnVer()  # declarative parser of nimble requires version to be literals
#version       = libver.Version
# since nimble@v0.16.4

author        = "Weitang Li (liwt),  lit (litlighilit)"
description   = "Python interpreter implemented in Nim, supporting JS backends"
license       = "MIT"
srcDir        = "."
installExt   = @["nim", "nims"]
installFiles  = @["LICENSE", "Parser/Grammar"]
skipDirs = @["tests"]
binDir        = "bin"

let srcName = "Python/npython"
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
  requires if pylibPre == "": x & ver
           else: pylibPre & x

pylib "pyrepr", " ^= 0.1.1"
pylib "jscompat", " ^= 0.1.4"
pylib "translateEscape", " ^= 0.1.0"

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

proc test(pre, pyExe, pyExeToCheckExists: string, args: openArray[string]) =
  let subTest =
    if args.len == 0: "asserts"
    else: args[0]
  if not fileExists pyExeToCheckExists:
    raise newException(OSError, "please firstly run `nimble " & pre & "`")
  withDir "tests/" & subTest:
    for i in listFiles ".":
      echo "testing " & i
      exec pyExe & ' ' & i

taskWithArgs test, "test, assuming after build":
  let pyExe = binPathWithoutExt.toExe
  test "build", pyExe, pyExe, args

taskWithArgs testNodeJs, "test nodejs backend, assuming after build":
  let
    pyExeFile = binPathWithoutExt & ".js"
    pyExe = "node " & pyExeFile
  test "buildJs", pyExe, pyExeFile, args

using args: openArray[string]
proc selfExecWithSrcAdd(cmd: string; args) =
  selfExec cmd & ' ' &
    args.quoteShellCommand & ' '& srcDir & '/' & srcName
proc selfExecBuildWithSrcAdd(cmd, outfile: string; args) =
  selfExecWithSrcAdd(cmd & " -o:" & outfile, args)

taskWithArgs buildDbg, "debug build, output product will be appended with a suffix `_d`":
  selfExecBuildWithSrcAdd "c -g", (binPathWithoutExt & "_d").toExe, args

taskWithArgs buildLib, "build shared library":
  selfExecBuildWithSrcAdd "c --app:lib", (binDir / namedBin[srcName].toDll), args

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
