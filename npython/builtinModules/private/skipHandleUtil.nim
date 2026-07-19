
from std/strutils import splitLines
from std/os import parentDir, `/`
import std/sets
export sets
const dir = currentSourcePath().parentDir
const skips = slurp(dir/"skipJs.txt").splitLines().toHashSet
proc shallSkip(modname: string): bool = modname in skips
template skipHandled(modname, body) {.dirty.} =
  bind shallSkip
  if not shallSkip(modname):
    body
export skipHandled
