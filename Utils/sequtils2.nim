
## called sequtils2 as having more apis over `./sequtils`

{.push hint[ConvFromXtoItselfNotNeeded]: off.}
proc rfind*[A; B: not string and not seq](key: typedesc; s: openArray[A], sub: B, start=0, stop=s.len): int =
  for i in countdown(stop-1, start):
    if key(s[i]) == key(sub): return i
  return -1

proc rfind*[A, B](key: typedesc; s: openArray[A], sub: openArray[B], start=0, stop=s.len): int =
  ## assert `start..<stop` in range of `0..<s.len`
  if sub.len == 0:
    return stop
  if sub.len > s.len - start:
    return -1
  result = 0
  for i in countdown(stop - sub.len, start):
    for j in 0..sub.len-1:
      result = i
      if key(sub[j]) != key(s[i+j]):
        result = -1
        break
    if result != -1: return
  return -1

proc rfind*[T](s: openArray[T], sub: T, start=0, stop=s.len): int = T.rfind(s, sub, start, stop)
proc rfind*[T](s: openArray[T], sub: openArray[T], start=0, stop=s.len): int = T.rfind(s, sub, start, stop)
{.pop.}
