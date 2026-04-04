
proc addr0*[T](x: T): ptr{.inline.} =
  # in case s.items is empty, XXX:assuming cap is alloc
  {.push boundChecks: off.}
  return x[0].addr
  {.pop.}
