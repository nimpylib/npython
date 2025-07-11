
import std/os
import std/strutils

when true:
  # copied from std/os, removed `readlink` part, see `XXX` below
  proc findExe*(exe: string, followSymlinks: bool = true;
                extensions: openArray[string]=ExeExts): string {.
    tags: [ReadDirEffect, ReadEnvEffect, ReadIOEffect].} =
    ## Searches for `exe` in the current working directory and then
    ## in directories listed in the ``PATH`` environment variable.
    ##
    ## Returns `""` if the `exe` cannot be found. `exe`
    ## is added the `ExeExts`_ file extensions if it has none.
    ##
    ## If the system supports symlinks it also resolves them until it
    ## meets the actual file. This behavior can be disabled if desired
    ## by setting `followSymlinks = false`.

    if exe.len == 0: return
    template checkCurrentDir() =
      for ext in extensions:
        result = addFileExt(exe, ext)
        if fileExists(result): return
    when defined(posix):
      if '/' in exe: checkCurrentDir()
    else:
      checkCurrentDir()
    let path = getEnv("PATH")
    for candidate in split(path, PathSep):
      if candidate.len == 0: continue
      when defined(windows):
        var x = (if candidate[0] == '"' and candidate[^1] == '"':
                  substr(candidate, 1, candidate.len-2) else: candidate) /
                exe
      else:
        var x = expandTilde(candidate) / exe
      for ext in extensions:
        var x = addFileExt(x, ext)
        if fileExists(x):
          # XXX: there was a branch of `when ...`, which doesn't work on nimvm
          #  due to `readlink`, so removed
          return x
    result = ""
