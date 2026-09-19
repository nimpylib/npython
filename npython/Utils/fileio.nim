## unified APIs for C and js backends,
## acting like std/syncio
when defined(nimPreviewSlimSystem):
  import std/assertions
  export assertions

import ../Utils/[compat]
import pkg/vsyncio/extraMeth/m_isatty
export isatty
when defined(js):
  import pkg/vsyncio as nio
else:
  import std/syncio as nio
export nio

proc flush_io*() =
  nio.stderr.flushFile
  nio.stdout.flushFile

