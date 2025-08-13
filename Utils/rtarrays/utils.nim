
template selfAsAccessor(p, self) =
  template p: untyped = self
template dollarImpl*(self: typed; getAccessor=selfAsAccessor){.dirty.} =
  result.add '['
  let L = self.len
  if L > 0:
    getAccessor(p, self)
    result.add $p[0]
    for i in 1..<L:
      result.add ", "
      result.add $p[i]
  result.add ']'

template chkIdx*(i, L: int) =
  when compileOption"boundChecks":
    if i not_in 0..<L:
      raise newException(IndexDefect, formatErrorIndexBound(i, L))

template atImpl*(self; p){.dirty.} =
  ## impl `@`, requires:
  ## - p.items int
  ## - p.pairs int
  let L = self.len
  when compiles(newSeqUninit[T]):
    result = newSeqUninit[T](self.len)
    when declared(copyMem):
      copyMem(result[0].addr, p[0].addr, L*sizeof(T))
    else:
      for i, v in p.pairs L:
        result[i] = v
  else:
    result = newSeqOfCap[T](L)
    for i in p.items L:
      result.add i
