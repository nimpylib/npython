

template `[]`*(p: ptr int, i: int): int = cast[ptr int](cast[int](p) + sizeof(int) * i)[]
template `[]=`*(p: ptr int, i: int; value: int) =
  bind `[]`
  `[]`(p, i) = value
