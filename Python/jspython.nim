
import ./cpython
import ../Utils/[compat, compat_io_os]

import std/jsffi except require

template isMain(b): bool = isMainModule and b
const
  nodejs = defined(nodejs)
  deno = defined(deno)
  dKarax = defined(karax)
when isMain(nodejs or deno):
  mayWaitFor main(commandLineParamsCompat())
else:
  when isMain(dKarax):
    import ./karaxpython
  elif isMainModule:
    import ./lifecycle
    pyInit(@[])
    mayWaitFor interactiveShell()
