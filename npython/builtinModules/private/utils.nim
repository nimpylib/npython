
template imp*(sub, ls) {.dirty.} =
  import ../../sub/ls

template impObjects*(ls) {.dirty.} =
  bind imp
  imp Objects, ls


