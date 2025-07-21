
# TODO: KMP

iterator findAllWithoutMem*[A, B](self: openArray[A], sub: openArray[B],
    start=0, key: typedesc): int =
  for i in start..(self.len - sub.len):
    var j = 0
    {.push hint[ConvFromXtoItselfNotNeeded]: off.}
    while j < sub.len and self[i + j].key == sub[j].key:
      j += 1
    {.pop.}
    if j == sub.len:
      yield i

proc findWithoutMem*[A, B](self: openArray[A], sub: openArray[B],
    start=0, key: typedesc): int =
  result = -1
  for i in findAllWithoutMem(self, sub, start, key):
    return i

iterator findAll*[T](s, sub: openArray[T], start=0): int =
  when declared(memmem):
    var start = start
    const N = sizeof(T)
    let subLen = sub.len
    if subLen != 0:
      while start < s.len:
        let found = memmem(s[start].addr, csize_t(s.len - start)*N, sub[0].addr, csize_t(subLen)*N)
        if found.isNil:
          break
        else:
          let n = (cast[int](found) -% cast[int](s[start].addr)) div N
          start += n
          yield n
  else:
    for i in findAllWithoutMem(s, sub, start, T):
      yield i


proc find*[T](s, sub: openArray[T], start=0): int =
  when declared(memmem):
    result = -1
    for i in findAll(s, sub, start):
      return i
  else:
    return findWithoutMem(s, sub, start, T)

proc contains*[T](s, sub: openArray[T]): bool{.inline.} = s.find(sub) > 0
