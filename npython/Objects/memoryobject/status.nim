
when defined(nimPreviewSlimSystem):
  import std/assertions
const NPySupportRawMemory*{.booldefine.} = not defined(js)
template requireRawMemorySupport* =
  bind doAssert
  static: doAssert NPySupportRawMemory, "This API is not supported in js backend"
template requireRawMemorySupport*(body) =
  bind NPySupportRawMemory
  when NPySupportRawMemory:
    body
