
template imp*(sub, ls) {.dirty.} =
  import ../../sub/ls

template impFrom*(sub, ls, sym) {.dirty.} =
  from ../../sub/ls import sym

template impObjects*(ls) {.dirty.} =
  bind imp
  imp Objects, ls


