
const PLATFORM* =
  when defined(js): "js"
  elif defined(windows): "win32"
  elif defined(macosx): "darwin"  # hostOS is macosx
  else: hostOS ## XXX: not right on all platform. PY-DIFF
  ## see nimpylib/nimpylib src/pylib/Lib/sys_impl/genplatform.nim
