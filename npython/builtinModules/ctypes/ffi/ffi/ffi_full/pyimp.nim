
import ../../../../private/[utils]
export utils
template impCtypes*(name) {.dirty.} =
  import ../../../name
template impFfi*(name) {.dirty.} =
  import ../../name

