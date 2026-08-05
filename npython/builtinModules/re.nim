import std/re

import ../Objects/[
  pyobject,
  moduleobjectImpl,
  stringobject,
  listobjectImpl,
  tupleobjectImpl,
  noneobject,
  numobjects,
  exceptionsImpl,
]
import ../Objects/exceptions/baseapi
import ./private/gen
import ../Python/getargs/dispatch

genModule re

declarePyType RePattern():
  regex: Regex

declarePyType ReMatch():
  text: PyStrObject
  first: int
  last: int
  groups: seq[string]


proc toRegexFlags(flags: int): set[RegexFlag] =
  result = {reStudy}
  if (flags and 2) != 0: result.incl reIgnoreCase
  if (flags and 8) != 0: result.incl reMultiLine
  if (flags and 16) != 0: result.incl reDotAll
  if (flags and 64) != 0: result.incl reExtended

proc compilePattern(pattern: PyObject; flags = 0): PyObject =
  if pattern.ofPyRePatternObject:
    return pattern
  if not pattern.ofPyStrObject:
    return newTypeError(newPyAscii("first argument must be string or compiled pattern"))
  try:
    let result = newPyRePatternSimple()
    result.regex = re($PyStrObject(pattern).str, toRegexFlags(flags))
    return result
  except RegexError as e:
    return newValueError(newPyStr e.msg)

proc makeMatch(pattern: PyRePatternObject; text: PyStrObject; start = 0): PyObject =
  var groups = newSeq[string](20)
  let bounds = findBounds($text.str, pattern.regex, groups, start)
  if bounds.first < 0:
    return pyNone
  let result = newPyReMatchSimple()
  result.text = text
  result.first = bounds.first
  result.last = bounds.last
  result.groups = groups
  result

proc implMatch(pattern: PyRePatternObject; text: PyStrObject): PyObject =
  let result = makeMatch(pattern, text)
  if result.isPyNone: return result
  if PyReMatchObject(result).first != 0: return pyNone
  result

proc implSearch(pattern: PyRePatternObject; text: PyStrObject): PyObject =
  makeMatch(pattern, text)

implRePatternMethod search(text: PyStrObject): implSearch(self, text)
implRePatternMethod match(text: PyStrObject): implMatch(self, text)

implReMatchMethod group(index: int):
  if index == 0:
    return newPyStr(($self.text.str)[self.first..self.last])
  if index < 1 or index > self.groups.len:
    return newIndexError(newPyAscii("no such group"))
  newPyStr self.groups[index - 1]

implReModuleMethod compile(pattern: PyObject, flags = 0): compilePattern(pattern, flags)

implReModuleMethod search(patternObj: PyObject, textObj: PyObject):
  let pattern = compilePattern(patternObj)
  retIfExc pattern
  if pattern.isPyNone or not pattern.ofPyRePatternObject:
    return pattern
  if not textObj.ofPyStrObject: return newTypeError(newPyAscii("expected string or bytes-like object"))
  implSearch(PyRePatternObject(pattern), PyStrObject(textObj))

implReModuleMethod match(patternObj: PyObject, textObj: PyObject):
  let pattern = compilePattern(patternObj)
  retIfExc pattern
  if not textObj.ofPyStrObject: return newTypeError(newPyAscii("expected string or bytes-like object"))
  implMatch(PyRePatternObject(pattern), PyStrObject(textObj))

implReModuleMethod findall(patternObj: PyObject, textObj: PyObject):
  let pattern = compilePattern(patternObj)
  retIfExc pattern
  if not textObj.ofPyStrObject: return newTypeError(newPyAscii("expected string or bytes-like object"))
  let regex = PyRePatternObject(pattern).regex
  let text = $PyStrObject(textObj).str
  var result = newPyList()
  var start = 0
  while start <= text.len:
    let found = find(text, regex, start)
    if found < 0: break
    var groups = newSeq[string](20)
    let bounds = findBounds(text, regex, groups, found)
    result.add newPyStr(text[bounds.first..bounds.last])
    start = if bounds.last < found: found + 1 else: bounds.last + 1
  result

implReModuleMethod sub(patternObj: PyObject, replacement: PyObject, textObj: PyObject):
  let pattern = compilePattern(patternObj)
  retIfExc pattern
  if not replacement.ofPyStrObject or not textObj.ofPyStrObject:
    return newTypeError(newPyAscii("sub() arguments must be strings"))
  newPyStr replace($PyStrObject(textObj).str, PyRePatternObject(pattern).regex,
    $PyStrObject(replacement).str)

implReModuleMethod split(patternObj: PyObject, textObj: PyObject):
  let pattern = compilePattern(patternObj)
  retIfExc pattern
  if not textObj.ofPyStrObject: return newTypeError(newPyAscii("expected string or bytes-like object"))
  var result = newPyList()
  for part in split($PyStrObject(textObj).str, PyRePatternObject(pattern).regex):
    result.add newPyStr part
  result
