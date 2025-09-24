
import std/os
const cprtFp = currentSourcePath() /../ "" /../ "LICENSE"
import std/strutils
proc Py_GetCopyrightImpl(): string =
  let all = readFile $cprtFp
  var start, stop = false
  template addl(L) =
    result.add L
  for line in all.splitLines(keepEol=true):
    if line == "\n":
      if start: stop = true
      else: start = true
      continue
    if stop: break
    if start:
      addl line
  result.stripLineEnd

proc Py_GetCopyright*(): string{.compileTime.} =
  Py_GetCopyrightImpl()
  #except IOError:

when isMainModule:
  static: echo Py_GetCopyright()
