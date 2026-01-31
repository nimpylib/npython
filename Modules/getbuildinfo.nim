
when defined(nimPreviewSlimSystem):
  import std/assertions

when NimMajor > 1 and not defined(nimscript) and not defined(js):
  from std/paths import `/../`, Path, parentDir
  from std/files import fileExists
  template fileExists(s: string): bool = fileExists Path s
  template `/../`(a, b: string): untyped = string(Path(a) /../ Path b)
  template parentDir(a: string): untyped = string(Path(a).parentDir)
elif defined(js):
  template fileExists(s: string): bool = compiles:(include s;)
  from std/os import `/../`, parentDir
else:
  from std/os import `/../`, parentDir, fileExists
import ./os_findExe_patch
from std/strutils import stripLineEnd, `%`

## see CPython/configure.ac

const BuildInfoCacheFile* = ".npython_build_info_cache.nim"  ## internal.
  ## We use this to ensure package `import`-able after `nimble install`
const hasCache = fileExists currentSourcePath() /../ BuildInfoCacheFile
const gitExe{.strdefine: "git".} = os_findExe_patch.findExe("git")
const git = (exe: gitExe)

when git.exe == "":
  {.warning: """
cannot find `git` executable, getbuildinfo will return empty string.
If you have git installed but not in PATH,
  please pass git absolute path via `-d:git=`
""".}
  template execEx(git: typeof(git); sub: string): untyped = (output: "", exitCode: 0)
else:
  const srcdir_git = currentSourcePath().parentDir /../ ".git"
  template execEx(git: typeof(git); sub: string): untyped =
    bind git
    gorgeEx(git.exe & " --git-dir " & srcdir_git & " " & sub)

const versionRes = git.execEx"rev-parse --short HEAD"
const useCache = hasCache and versionRes.exitCode != 0
when useCache:
  import std/macros
  macro imp(s: static[string]) = nnkIncludeStmt.newTree newStrLitNode s
  imp BuildInfoCacheFile
else:
  template exec(git: typeof(git); sub: string): string =
    let res = execEx(git, sub)
    assert res.exitCode == 0, res.output
    var outp = res.output
    outp.stripLineEnd
    outp
  const
    version = versionRes.output
    tag = git.exec"describe --all --always --dirty"
    branch = git.exec"name-rev --name-only HEAD"

proc gitversion*: string = version  ## Py_gitversion
proc gitidentifier*: string =
  result = tag
  if result != "" and result != "undefined":
    return
  result = branch

when not useCache:
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
  const
    buildInfo = getBuildInfo()

proc genBuildCacheContent*(): string =
  ## internal.
  ## 
  ## to generate `BuildInfoCacheFile`_
  """
const
  version = "$#"
  tag = "$#"
  branch = "$#"
  buildInfo = "$#"
  """ % [version, tag, branch, buildInfo]



proc Py_GetBuildInfo*: string = buildinfo
