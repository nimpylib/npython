
when defined(js):
  import pkg/pystrbytes_decl
  export pystrbytes_decl
  type PyPathStr* = PyStr
else:
  type PyPathStr* = distinct string

  using self: PyPathStr
  converter `$`*(self): string = string self

