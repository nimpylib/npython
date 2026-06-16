
include ./comm
imp stringobject

proc equivFormat(dest: Py_buffer; src: Py_buffer): bool {.inline.} =
  ##  This is not a general function for determining format equivalence.
  ##    It is used in copy_single() and copy_buffer() to weed out non-matching
  ##    formats. Skipping the '@' character is specifically used in slice
  ##    assignments, where the lvalue is already known to have a single character
  ##    format. This is a performance hack that could be rewritten (if properly
  ##    benchmarked).
  assert(dest.format.isNil.not and src.format.isNil.not)
  template skip1At(s: cstring): cstring =
    if s[0] == '@': cast[cstring](cast[int](s) + 1)
    else: s
  let
    dfmt = skip1At(dest.format)
    sfmt = skip1At(src.format)
  dfmt == sfmt and dest.itemsize == src.itemsize

proc equivShape(dest: Py_buffer; src: Py_buffer): bool {.inline.} =
  ##  Two shapes are equivalent if they are either equal or identical up
  ##    to a zero element at the same position. For example, in NumPy arrays
  ##    the shapes [1, 0, 5] and [1, 0, 7] are equivalent.
  if dest.ndim != src.ndim:
    return
  for i in 0..<dest.ndim:
    if dest.shape[i] != src.shape[i]:
      return false
    if dest.shape[i] == 0:
      break
  return true

proc equiv_structure*(dest: Py_buffer; src: Py_buffer): PyBaseErrorObject =
  ##  Check that the logical structure of the destination and source buffers
  ##    is identical.
  if not equivFormat(dest, src) or not equivShape(dest, src):
    return newValueError newPyAscii"memoryview assignment: lvalue and rvalue have different structures"
