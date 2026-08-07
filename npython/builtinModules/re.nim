import std/options
import pkg/pyre

import ../Objects/[
  pyobject,
  moduleobjectImpl,
  byteobjectsImpl,
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
declarePyError Pattern, Base:
  msg{.member.}: PyStrObject
  pattern{.member, nil2none.}: PyObject
  pos{.member, nil2none.}: PyObject
  lineno{.member, nil2none.}: PyObject
  colno{.member, nil2none.}: PyObject
genProperty ReModule, "PatternError", PatternError, pyPatternErrorObjectType

declarePyType RePattern():
  regex: pyre.Regex

declarePyType ReMatch():
  text: PyStrObject
  value: pyre.Match

proc setPatternErrorLocation(error: PyPatternErrorObject; pattern, pos: PyObject): PyObject =
  if pattern.isPyNone or pos.isPyNone:
    return pyNone
  if not pattern.ofPyStrObject or not pos.ofPyIntObject:
    return newTypeError(newPyAscii("pattern must be a string and pos must be an integer"))
  let patternText = $PyStrObject(pattern).str
  let position = PyIntObject(pos).toSomeSignedIntUnsafe[:int]
  var lineno = 1
  var lineStart = -1
  for index in 0 ..< min(position, patternText.len):
    if patternText[index] == '\n':
      inc lineno
      lineStart = index
  error.lineno = newPyInt lineno
  error.colno = newPyInt (position - lineStart)
  pyNone

implPatternErrorMagic init(msg: PyStrObject, pattern=pyNoneObj, pos=pyNoneObj):
  self.msg = msg
  if not pattern.isPyNone:
    self.pattern = pattern
  if not pos.isPyNone:
    self.pos = pos
  retIfExc setPatternErrorLocation(self, pattern, pos)
  self.args = newPyTuple [msg]
  if not pattern.isPyNone and not pos.isPyNone:
    let position = PyIntObject(pos).toSomeSignedIntUnsafe[:int]
    self.args = newPyTuple [newPyStr($msg.str &
      " at position " & $position)]
  pyNone

proc newPatternError*(error: pyre.PatternError): PyPatternErrorObject =
  result = newPatternError(newPyStr error.msg)
  result.msg = newPyStr error.msg
  if error.pattern.len != 0:
    result.pattern = newPyStr error.pattern
  if error.pos >= 0:
    result.pos = newPyInt error.pos
    var lineno = 1
    var lineStart = -1
    for index in 0 ..< error.pos:
      if error.pattern[index] == '\n':
        inc lineno
        lineStart = index
    result.lineno = newPyInt lineno
    result.colno = newPyInt (error.pos - lineStart)
    result.args = newPyTuple [newPyStr(error.msg & " at position " & $error.pos)]

proc compilePattern(pattern: PyObject; flags = 0): PyObject =
  if pattern.ofPyRePatternObject:
    return pattern
  if not pattern.ofPyStrObject:
    return newTypeError(newPyAscii("first argument must be string or compiled pattern"))
  try:
    let res = newPyRePatternSimple()
    res.regex = pyre.compile($PyStrObject(pattern).str, flags)
    return res
  except PatternError as e:
    return newPatternError(e)

proc regexText(textObj: PyObject; text: var string; matchText: var PyStrObject): PyObject =
  if textObj.ofPyStrObject:
    matchText = PyStrObject(textObj)
    text = $matchText.str
  elif textObj.ofPyBytesObject:
    text = PyBytesObject(textObj).asString
    matchText = newPyStr text
  elif textObj.ofPyByteArrayObject:
    text = PyByteArrayObject(textObj).asString
    matchText = newPyStr text
  else:
    return newTypeError(newPyAscii("expected string or bytes-like object"))
  pyNone

proc makeMatch(pattern: PyRePatternObject; text: string; matchText: PyStrObject;
               anchored = false): PyObject =
  try:
    let found = if anchored: pyre.match(pattern.regex, text)
                else: pyre.search(pattern.regex, text)
    if found.isNone:
      return pyNone
    let res = newPyReMatchSimple()
    res.text = matchText
    res.value = found.get
    res
  except PatternError as e:
    newPatternError(e)

proc implMatch(pattern: PyRePatternObject; text: string; matchText: PyStrObject): PyObject =
  makeMatch(pattern, text, matchText, anchored = true)

proc implSearch(pattern: PyRePatternObject; text: string; matchText: PyStrObject): PyObject =
  makeMatch(pattern, text, matchText)

implRePatternMethod search(textObj: PyObject):
  var text: string
  var matchText: PyStrObject
  retIfExc regexText(textObj, text, matchText)
  implSearch(self, text, matchText)

implRePatternMethod match(textObj: PyObject):
  var text: string
  var matchText: PyStrObject
  retIfExc regexText(textObj, text, matchText)
  implMatch(self, text, matchText)

implReMatchMethod group(index: int):
  var value: Option[string]
  try:
    value = self.value.group(index)
  except IndexDefect:
    return newIndexError(newPyAscii("no such group"))
  if value.isNone: pyNone else: newPyStr value.get

implReModuleMethod compile(pattern: PyObject, flags = 0): compilePattern(pattern, flags)

implReModuleMethod search(patternObj: PyObject, textObj: PyObject):
  let pattern = compilePattern(patternObj)
  retIfExc pattern
  if pattern.isPyNone or not pattern.ofPyRePatternObject:
    return pattern
  var text: string
  var matchText: PyStrObject
  retIfExc regexText(textObj, text, matchText)
  implSearch(PyRePatternObject(pattern), text, matchText)

implReModuleMethod match(patternObj: PyObject, textObj: PyObject):
  let pattern = compilePattern(patternObj)
  retIfExc pattern
  var text: string
  var matchText: PyStrObject
  retIfExc regexText(textObj, text, matchText)
  implMatch(PyRePatternObject(pattern), text, matchText)

implReModuleMethod findall(patternObj: PyObject, textObj: PyObject):
  let pattern = compilePattern(patternObj)
  retIfExc pattern
  var text: string
  var matchText: PyStrObject
  retIfExc regexText(textObj, text, matchText)
  let res = newPyList()
  try:
    let regex = PyRePatternObject(pattern).regex
    let captureCount = regex.captureCount
    if captureCount == 0:
      for found in pyre.finditer(regex, text):
        res.add newPyStr found.group().get
    elif captureCount == 1:
      for captures in pyre.findallCaptures(regex, text):
        res.add newPyStr captures[0]
    else:
      for captures in pyre.findallCaptures(regex, text):
        var groups: seq[PyObject]
        for capture in captures:
          groups.add newPyStr capture
        res.add newPyTuple groups
  except PatternError as e:
    return newPatternError(e)
  result = res

implReModuleMethod sub(patternObj: PyObject, replacement: PyObject, textObj: PyObject):
  let pattern = compilePattern(patternObj)
  retIfExc pattern
  if not replacement.ofPyStrObject:
    return newTypeError(newPyAscii("sub() arguments must be strings"))
  var text: string
  var matchText: PyStrObject
  retIfExc regexText(textObj, text, matchText)
  try:
    newPyStr pyre.sub(PyRePatternObject(pattern).regex,
      $PyStrObject(replacement).str, text)
  except PatternError as e:
    newPatternError(e)

implReModuleMethod subn(patternObj: PyObject, replacement: PyObject, textObj: PyObject):
  let pattern = compilePattern(patternObj)
  retIfExc pattern
  if not replacement.ofPyStrObject:
    return newTypeError(newPyAscii("subn() arguments must be strings"))
  var text: string
  var matchText: PyStrObject
  retIfExc regexText(textObj, text, matchText)
  try:
    let replaced = pyre.subn(PyRePatternObject(pattern).regex,
      $PyStrObject(replacement).str, text)
    newPyTuple([newPyStr replaced.value, newPyInt replaced.count])
  except PatternError as e:
    newPatternError(e)

implReModuleMethod escape(textObj: PyObject):
  if not textObj.ofPyStrObject:
    return newTypeError(newPyAscii("escape() argument must be str"))
  try:
    newPyStr pyre.escape($PyStrObject(textObj).str)
  except PatternError as e:
    newPatternError(e)

implReModuleMethod split(patternObj: PyObject, textObj: PyObject):
  let pattern = compilePattern(patternObj)
  retIfExc pattern
  var text: string
  var matchText: PyStrObject
  retIfExc regexText(textObj, text, matchText)
  let res = newPyList()
  try:
    for part in pyre.split(PyRePatternObject(pattern).regex, text):
      res.add newPyStr part
  except PatternError as e:
    return newPatternError(e)
  result = res
