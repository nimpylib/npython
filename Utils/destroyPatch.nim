
template sinceNim(ma, mi, pa): bool =
  (NimMajor, NimMinor, NimPatch) >= (ma, mi, pa)
const Js = defined(js)
when not Js and sinceNim(2,1,1) or
    Js and sinceNim(2,3,2):
  template defdestroy*(self; Self; body){.dirty.} =
    proc `=destroy`*(self: Self) = body
else:
  template defdestroy*(self; Self; body){.dirty.} =
    proc `=destroy`*(self: var Self) = body


template defdestroy*(Self; body){.dirty.} =
  defdestroy self, Self, body

