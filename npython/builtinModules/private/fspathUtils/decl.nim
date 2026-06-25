
type PyPathStr* = distinct string

using self: PyPathStr
converter `$`*(self): string = string self

