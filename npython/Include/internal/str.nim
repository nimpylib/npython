
type
  Str* = string
  Char* = typeof (var s: Str; s[0])

const StrEmpty* = default Str
proc isEmpty*(s: Str): bool = s==""
