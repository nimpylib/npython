## params' metadata
template convertVia*(f: typed) {.pragma.}  ## `converter` is reserved word in Nim
template startKwOnly* {.pragma.}  ## Python's `*` in param list, e.g.
  ## for Python's `a: int, *, b=1`,
  ## in npython you shall write as `a: int, b{.startKwOnly.}=1`

