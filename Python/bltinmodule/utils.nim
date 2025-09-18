
template regfunc*(f) =
  registerBltinFunction astToStr(f), `builtin f`

template regobj*(f) =
  registerBltinObject astToStr(f), `py f ObjectType`
