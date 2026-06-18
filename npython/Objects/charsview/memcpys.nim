## shim for js
static:assert defined(js)

import ./decl
using
  dest: var CharsView
  src: CharsView
proc copyMem*(dest; src; n: int) =
  for i in 0..<n: dest[i] = src[i]
proc moveMem*(dest; src; n: int) =
  for i in 0..<n: dest[i] = src[i]
