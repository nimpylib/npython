from "Python/versionInfo" import Version
import std/macros; macro asgnVer = quote do: version = `Version`
asgnVer()  # declarative parser of nimble requires version to be literals
#version       = libver.Version
# since nimble@v0.16.4

author        = "Weitang Li (liwt),  lit (litlighilit)"
description   = "Python interpreter implemented in Nim, supporting JS backends"
license       = "MIT"
srcDir        = "Python"
binDir        = "bin"

let srcName = "python"
namedBin[srcName] = "npython"

requires  "nim >= 1.6.14"  # 2.* (at least till 2.3.1) is okey, too.
when declared(feature):  # nimble v0.18+
  feature "playground":
    requires "karax"

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

taskWithArgs buildJs, "build JS. supported backends: " &
    "-d:nodejs|-d:deno|-d:jsAlert":
  selfExec "js -o:" & binPathWithoutExt & ".js " &
    args.quoteShellCommand & ' '& srcDir & '/' & srcName

taskRequires "buildKarax", "karax"
taskWithArgs buildKarax, "build html page with karax":
  selfExec "r --hints:off -d:release Tools/mykarun -d:karax " & " --appName=" & namedBin[srcName] & ' ' &
    args.quoteShellCommand & ' '& srcDir & '/' & srcName
