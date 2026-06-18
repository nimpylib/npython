
when defined(js):
  type CharsView* = seq[char]
else:
  type CharsView* = cstring  ## impl is unstable. It's UB if setitem to PyBytes's CharsView
  ## and in JS backend, currently it's just a copy, not a real view

template genCharsViewDecl*(T) {.dirty.} =
  when defined(js):
    type T = var CharsView
  else:
    type T = CharsView
