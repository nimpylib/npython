import "Python/versionInfo" as libver
version       = libver.Version
author        = "Weitang Li, litlighilit"
description   = "(Subset of) Python programming language implemented in Nim"
license       = "CPython license"
srcDir        = "Python"
binDir        = "bin"

let srcName = "python"
namedBin[srcName] = "npython"

requires  "nim >= 1.6.14"  # 2.* (at least till 2.3.1) is okey, too.

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
