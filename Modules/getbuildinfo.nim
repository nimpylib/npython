

when NimMajor > 1:
  from std/paths import `/../`, Path, parentDir
  template `/../`(a, b: string): untyped = string(Path(a) /../ Path b)
  template parentDir(a: string): untyped = string(Path(a).parentDir)
else:
  from std/os import `/../`, parentDir
import ./os_findExe_patch
from std/strutils import stripLineEnd

## see CPython/configure.ac

const gitExe{.strdefine: "git".} = findExe("git")
const git = (exe: gitExe)
when git.exe == "":
  template exec(git; sub: string): string = ""
else:
  const srcdir_git = currentSourcePath().parentDir /../ ".git"
  template exec(git: typeof(git); sub: string): string =
    bind srcdir_git
    let res = gorgeEx(git.exe & " --git-dir " & srcdir_git & " " & sub)
    assert res.exitCode == 0, res.output
    var outp = res.output
    outp.stripLineEnd
    outp

const
  version = git.exec"rev-parse --short HEAD"
  tag = git.exec"describe --all --always --dirty"
  branch = git.exec"name-rev --name-only HEAD"

proc gitidentifier*: string =
  result = tag
  if result != "" and result != "undefined":
    return
  result = branch


proc getBuildInfo: string{.compileTime.} =
  let revision = version
  result = gitidentifier()
  if revision != "":
    result.add ':'
    result.add revision

  result.add ", "

  #result.add &"{CompileDate:.20s}, {CompileTime:.9s}"
  result.add CompileDate.substr(0, 19)
  result.add ", "
  result.add CompileTime.substr(0, 8)

const buildinfo = getBuildInfo()
proc Py_GetBuildInfo*: string = buildinfo
