
template dispatchUnary*(op){.dirty.} =
  proc `op`*(self: PyIntObject): PyIntObject{.inline.} = newPyInt op(self.v)
template dispatchBin*(op){.dirty.} =
  proc `op`*(a, b: PyIntObject): PyIntObject{.inline.} = newPyInt op(a.v, b.v)
