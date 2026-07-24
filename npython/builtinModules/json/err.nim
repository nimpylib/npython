
import std/strformat
import ../private/[utils]


impObjects [
  pyobject,
  exceptions,
  stringobjectImpl,
]

declarePyError JSONDecode, Value:
  msg{.member.}: PyStrObject
  doc{.member.}: PyStrObject
  pos{.member.}: int
  lineno{.member.}: int
  colno{.member.}: int


proc newJSONDecodeError*(msg, doc: PyStrObject, pos: int, lineno: int): PyBaseErrorObject =
  let c = doc.rfind('\n', 0, pos)
  var colno = pos
  if c >= 0: colno -= c

  let detailedMsg = msg & newPyAscii fmt": line {lineno} column {colno} (char {pos})"
  let res = newJSONDecodeError(detailedMsg)
  res.msg = msg
  res.doc = doc
  res.pos = pos
  res.lineno = lineno
  res.colno = colno
  result = res

proc newJSONDecodeError*(msg, doc: PyStrObject, pos: int): PyBaseErrorObject =
  let lineno = doc.count('\n', 0, pos) + 1
  newJSONDecodeError(msg, doc, pos, lineno)
