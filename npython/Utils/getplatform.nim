
const PLATFORM* =
  when defined(js):
    # compiling with `-d:nodejs` means being not runnable on others
    when defined(nodejs): "nodejs"
    elif defined(deno): "deno"
    else: "js"
  elif defined(windows): "win32"
  elif defined(macosx): "darwin"  # hostOS is macosx
  else: hostOS ## XXX: not right on all platform. PY-DIFF
  ## see nimpylib/nimpylib src/pylib/Lib/sys_impl/genplatform.nim
