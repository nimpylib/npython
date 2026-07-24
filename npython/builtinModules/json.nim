import std/json as nimJson
import std/streams
import std/parsejson
import std/math

import std/strformat

import ./private/[utils, gen]

impObjects [
  pyobject,
  exceptions,
  moduleobjectImpl,
  noneobject,
  boolobject,
  stringobjectImpl,
  byteobjects,
  listobject,
  tupleobject,
  dictobject,
  numobjects,
]
impObjects exceptions/ioerror
impObjects exceptions/oserr/convert
#imp Python, getargs/tovals
import pkg/intobject

genModule json

declarePyError JSONDecode, Value:
  msg{.member.}: PyStrObject
  doc{.member.}: PyStrObject
  pos{.member.}: int
  lineno{.member.}: int
  colno{.member.}: int

template gen_var(nam, variable) {.dirty.} =
  genProperty JsonModule, astToStr(nam), nam: variable
gen_var JSONDecodeError, pyJSONDecodeErrorObjectType

proc newJSONDecodeError(msg, doc: PyStrObject, pos: int, lineno: int): PyBaseErrorObject =
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
proc newJSONDecodeError(msg, doc: PyStrObject, pos: int): PyBaseErrorObject =
  let lineno = doc.count('\n', 0, pos) + 1
  newJSONDecodeError(msg, doc, pos, lineno)

#XXX: why not use std/json:
#[
- we parse int not as fixed size, but tho there's `rawIntegers` param for parseJson,
  but we just cannot distinguish string with rawInteger node
- so as for `rawFloats`; in addition, python's json accepts
  `NaN`, `Infinity`, `-Infinity` as float, which is not valid RFC 7159 JSON.
]#
template retE(p: var JsonParser, msg: PyStrObject) =
  return newJSONDecodeError(msg, newPyStr p.buf, p.bufpos, p.lineNumber)
template myeat(p: var JsonParser, ttok: TokKind) =
  if p.tok == ttok: discard getTok(p)
  else: p.retE newPyAscii("excepted " & $ttok)
proc parseJsonAsPy(p: var JsonParser, res: var PyObject): PyBaseErrorObject {.raises: [IOError, OSError].} =
  ## Parses JSON from a JSON Parser `p`.
  case p.tok
  of tkString:
    res = newPyStr p.a
    discard getTok(p)
  of tkInt:
    if p.a == "-":
      discard getTok(p)
      if p.tok != tkError or p.a != "Infinity":
        p.retE newPyAscii "invalid token"
      res = newPyFloat NegInf
      discard getTok(p)
    else:
      try:
        res = newPyInt p.a
      except ValueError as e:
        return newValueError newPyAscii e.msg
      discard getTok(p)
  of tkFloat:
    var fres: PyFloatObject
    let exc = PyFloat_FromString(newPyAscii p.a, fres)
    if not exc.isNil:
      p.retE PyStrObject exc.args[0]
    res = fres
    discard getTok(p)
  of tkTrue:
    res = pyTrueObj
    discard getTok(p)
  of tkFalse:
    res = pyFalseObj
    discard getTok(p)
  of tkNull:
    res = pyNone
    discard getTok(p)
  of tkCurlyLe:
    #if depth > DepthLimit: raiseParseErr(p, "}")
    let resObj: PyDictObject = newPyDict() #newJObject()
    res = resObj
    discard getTok(p)
    while p.tok != tkCurlyRi:
      if p.tok != tkString:
        p.retE newPyAscii "string literal as key"
      var key = newPyStr p.a
      discard getTok(p)
      myeat(p, tkColon)
      var val: PyObject
      retIfExc p.parseJsonAsPy val
      resObj[key] = val
      if p.tok != tkComma: break
      discard getTok(p)
    myeat(p, tkCurlyRi)
  of tkBracketLe:
    #if depth > DepthLimit: raiseParseErr(p, "]")
    let resObj: PyListObject = newPyList() #newJArray()
    res = resObj
    discard getTok(p)
    while p.tok != tkBracketRi:
      var val: PyObject
      retIfExc p.parseJsonAsPy val
      resObj.add(val) #parseJson(p, rawIntegers, rawFloats, depth+1))
      if p.tok != tkComma: break
      discard getTok(p)
    myeat(p, tkBracketRi)
  of tkError:
    case p.a
    of "NaN":
      res = newPyFloat NaN
    of "Infinity":
      res = newPyFloat Inf
    # -Infinity is handled in tkInt case
    else:
      p.retE newPyAscii "invalid token"
    discard getTok(p)
  of tkCurlyRi, tkBracketRi, tkColon, tkComma, tkEof:
    p.retE newPyAscii "{" & " excepted"

proc encodeString(value: string): string = $(%value)

proc toJsonString(obj: PyObject, output: var string): PyBaseErrorObject =
  if obj.isPyNone:
    output.add "null"
  elif obj.ofPyBoolObject:
    output.add(if PyBoolObject(obj).isPyTrue: "true" else: "false")
  elif obj.ofPyIntObject:
    output.add $PyIntObject(obj).v
  elif obj.ofPyFloatObject:
    let value = PyFloatObject(obj).v
    if value.isNaN:
      output.add "NaN"
    elif value == Inf:
      output.add "Infinity"
    elif value == NegInf:
      output.add "-Infinity"
    else:
      output.add $value
  elif obj.ofPyStrObject:
    output.add encodeString(PyStrObject(obj).asUTF8)
  elif obj.ofPyListObject or obj.ofPyTupleObject:
    output.add '['
    var first = true
    template addItem(item: PyObject) =
      if first:
        first = false
      else:
        output.add ", "
      let exc = toJsonString(item, output)
      if not exc.isNil:
        return exc
    if obj.ofPyListObject:
      for item in PyListObject(obj):
        addItem item
    else:
      for item in PyTupleObject(obj):
        addItem item
    output.add ']'
  elif obj.ofPyDictObject:
    output.add '{'
    var first = true
    for key, value in PyDictObject(obj).pairs:
      if not key.ofPyStrObject:
        return newTypeError newPyAscii(
          "keys must be str, int, float, bool or None, not " & key.typeName)
      if first:
        first = false
      else:
        output.add ", "
      output.add encodeString(PyStrObject(key).asUTF8)
      output.add ": "
      let exc = toJsonString(value, output)
      if not exc.isNil:
        return exc
    output.add '}'
  else:
    return newTypeError newPyAscii(
      "Object of type " & obj.typeName & " is not JSON serializable")

proc decodeJson(s: Stream): PyObject =
  const filename = ""
  handleOsErrRetPyObj:
    try:
      var p: JsonParser = default(JsonParser)
      p.open(s, filename)
      try:
        discard getTok(p) # read first token
        retIfExc p.parseJsonAsPy result #parseJson(p, rawIntegers, rawFloats, 0)
        myeat(p, tkEof) # check if there is no extra data
      finally:
        p.close()
    except IOError as exc: return newIOError exc

proc decodeJson(s: string): PyObject = decodeJson newStringStream(s)

proc toString(s: openArray[char]): string =
  result = newStringUninit(s.len)
  for i, c in s: result[i] = c
proc decodeJson(s: openArray[char]): PyObject = decodeJson(toString(s))

proc loads*(s: PyStrObject): PyObject = decodeJson(s.asUTF8)
proc loads*(s: PyBytesObject|PybytearrayObject): PyObject = decodeJson(s.items)

proc loads*(s: PyObject): PyObject =
  if s.ofPyStrObject: loads(PyStrObject(s))
  elif s.ofPyBytesObject: loads(PyBytesObject(s))
  elif s.ofPyByteArrayObject: loads(PyByteArrayObject(s))
  else:
    newTypeError newPyStr(
      "the JSON object must be str, bytes or bytearray, not " & s.typeName)

proc dumps(obj: PyObject): PyObject =
  var encoded = ""
  let exc = toJsonString(obj, encoded)
  retIfExc exc
  newPyStr encoded

#TODO:io: load, dump
#TODO:json: kw
impljsonModuleMethod loads(s): loads(s)
impljsonModuleMethod dumps(obj): dumps(obj)
