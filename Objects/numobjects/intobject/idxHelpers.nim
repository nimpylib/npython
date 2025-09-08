## for external use

import ./[decl, ops]
# used in list and tuple
template getIndex*(obj: PyIntObject, size: int, sizeOpIdx: untyped = `<=`): int =
  var idx = obj.toIntOrRetOF
  if idx < 0:
    idx = size + idx
  if (idx < 0) or (sizeOpIdx(size, idx)):
    let msg = "index out of range. idx: " & $idx & ", len: " & $size
    return newIndexError newPyAscii(msg)
  idx

proc getClampedIndex*(idx: int, size: int): int =
  result = idx
  if result < 0:
    result += size
  if result < 0: result = 0
  elif size <= result: result = size


template getClampedIndex*(obj: PyIntObject, size: int): int =
  ## like `getIndex`_ but clamping result in `0..<size`
  getClampedIndex obj.toIntOrRetOF, size
