
import ./rawMem

type
  RtArrayView*[T] = distinct ptr UncheckedArray[T]

proc `[]`*[T](self: RtArrayView[T]; i: int): T =
  cast[ptr UncheckedArray[T]](self)[i]
proc `[]=`*[T](self: RtArrayView[T]; i: int, val: T) =
  cast[ptr UncheckedArray[T]](self)[i] = val
converter toPtr*[T](v: RtArrayView[T]): ptr T = cast[ptr T](v)
converter toPointer*[T](v: RtArrayView[T]): pointer = cast[pointer](v)

proc newRtArrayView*[T](arr: ptr T): RtArrayView[T] = cast[RtArrayView[T]](arr)  ## unstable. for C-arrays
proc newView*[T](arr: var RtArray[T]): RtArrayView[T] = cast[RtArrayView[T]](arr.getRawData)
proc newView*[T](arr: RtArray[T]): RtArrayView[T] = cast[RtArrayView[T]](arr.getRORawData)

proc isNil*(self: RtArrayView): bool{.borrow.}
