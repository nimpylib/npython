
import ../numobjects/intobject/[idxHelpers]

template prefind*{.dirty.} =
  bind getClampedIndex
  let le = self.len
  let
    start = start.getClampedIndex le
    stop = stop.getClampedIndex le
