
when defined(nimPreviewSlimSystem):
  import std/assertions
  export assertions
template imp(ls) {.dirty.} =
  import ../../ls

imp [
  exceptions,
  pybuffer,
]
