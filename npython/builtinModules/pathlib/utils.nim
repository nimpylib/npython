

when defined(js):
  from pkg/posixos/consts import name
  let os_name* = string name
template winOrPosix*(win, posix): untyped =
  when defined(windows): win
  elif defined(js):
    if os_name == "nt": win
    else: posix
  else: posix
