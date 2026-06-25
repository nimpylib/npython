
import ../../private/[utils, dispatch,]
template impfspathUtils*(ls) {.dirty.} =
  import ../../private/fspathUtils/ls
export utils, dispatch
