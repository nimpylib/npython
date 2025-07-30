## Nim lacks `find` with start, stop param
## 
## .. note:: functions in this module assume `start..<stop` in valid range.
##   (a.k.a. it's caller's responsibility to check `0 <= start <= stop < s.len`)
# TODO: KMP

iterator findAllWithoutMem*[A, B](key: typedesc, self: openArray[A], sub: openArray[B],
    start=0, stop=self.len): int =
  for i in start..(stop - sub.len):
    var j = 0
    {.push hint[ConvFromXtoItselfNotNeeded]: off.}
    while j < sub.len and self[i + j].key == sub[j].key:
      j += 1
    {.pop.}
    if j == sub.len:
      yield i

proc findWithoutMem*[A, B](key: typedesc, self: openArray[A], sub: openArray[B],
    start=0, stop=self.len): int =
  result = -1
  for i in findAllWithoutMem(key, self, sub, start, stop):
    return i

iterator findAll*[T](s, sub: openArray[T], start=0, stop: int): int =
  when declared(memmem):
    var start = start
    const N = sizeof(T)
    let subLen = sub.len
    if subLen != 0:
      while start < stop:
        let found = memmem(s[start].addr, csize_t(stop - start)*N, sub[0].addr, csize_t(subLen)*N)
        if found.isNil:
          break
        else:
          let n = (cast[int](found) -% cast[int](s[start].addr)) div N
          start += n
          yield n
  else:
    for i in findAllWithoutMem(T, s, sub, start, stop):
      yield i

# XXX: NIM-BUG: cannot directly use `start=0, stop=s.len`
#  here use overload to bypass `Error: internal error: expr: var not init :tmp_2382366184`
iterator findAll*[T](s, sub: openArray[T], start=0): int =
  for i in s.findAll(sub, start, s.len): yield i

proc find*[T](s, sub: openArray[T], start=0, stop=s.len): int =
  when declared(memmem):
    result = -1
    for i in findAll(s, sub, start, stop):
      return i
  else:
    return findWithoutMem(T, s, sub, start, stop)

template wrapOA(fd){.dirty.} =
  template fd*[T](s: openArray[T], x: T, start: int, stop: int): untyped =
    fd(s.toOpenArray(start, stop-1), x)
  template fd*[T](s: openArray[T], x: T, start: int): untyped =
    fd(s, x, start, s.len)
export system.find
wrapOA find

iterator findAll*[T](s: openArray[T], x: T): int =
  var i = 0
  while true:
    i = s.find(x, i)
    if i >= 0: yield i
    else: break


wrapOA findAll

proc contains*[T](s, sub: openArray[T]): bool{.inline.} = s.find(sub) > 0
