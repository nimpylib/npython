

import ../../[
  pyobject,
  exceptions,
  stringobject,
]
template processLine[T](s: T; lineno: int; keepEnd: bool): T =
  var
    idx = -1
    curLineno = 0
  var
    prevR = false
    justR = false
  var res: T
  block retRes:
    for i, c in s:
      case c
      of typeof(c) '\n':
        let tprevR = prevR
        prevR = false
        if tprevR and idx+1 == i:
          justR = true
        else:
          justR = false
          curLineno.inc
      of typeof(c) '\r':
        prevR = true
        justR = false
        curLineno.inc
      #TODO:newline of others
      else:
        continue
      if curLineno == lineno:
        var ii = i
        if keepEnd:
          ii.inc
          if (c == typeof(c) '\r') and ii < s.len and (s[ii] == typeof(c) '\n'):
            ii.inc
        elif justR: ii.dec
        res = s[idx+1..<ii]
        break retRes

      idx = i
    if curLineno + 1 == lineno:
      res = s[idx+1..^1]
    else:
      return nil
  res


proc getLineOf*(s: PyStrObject, lineno: int, keepEnd: bool): PyStrObject =
  ## `lineno` counts from 1
  ##
  ## returns nil if lineno is out of range
  if lineno <= 0: return
  if s.isAscii:
    newPyAscii s.str.asciiStr.processLine(lineno, keepEnd)
  else:
    newPyStr s.str.unicodeStr.processLine(lineno, keepEnd)

