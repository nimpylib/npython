import std/json as nimJson
import std/streams
import std/parsejson
import std/math

import ./private/[utils, gen]

impObjects [
  pyobject,
  exceptions,
  moduleobjectImpl,
  noneobject,
  boolobject,
  stringobject,
  byteobjects,
  listobject,
  tupleobject,
  dictobject,
  numobjects,
]
#imp Python, getargs/tovals
import pkg/intobject

genModule json

#XXX: why not use std/json:
#[
- we parse int not as fixed size, but tho there's `rawIntegers` param for parseJson,
  but we just cannot distinguish string with rawInteger node
- so as for `rawFloats`; in addition, python's json accepts
  `NaN`, `Infinity`, `-Infinity` as float, which is not valid RFC 7159 JSON.
]#
proc parseJsonAsPy(p: var JsonParser): PyObject =
  ## Parses JSON from a JSON Parser `p`.
  case p.tok
  of tkString:
    result = newPyStr p.a
    discard getTok(p)
  of tkInt:
    result = newPyInt p.a
    discard getTok(p)
  of tkFloat:
    result = PyFloat_FromString newPyAscii p.a
    discard getTok(p)
  of tkTrue:
    result = pyTrueObj
    discard getTok(p)
  of tkFalse:
    result = pyFalseObj
    discard getTok(p)
  of tkNull:
    result = pyNone
    discard getTok(p)
  of tkCurlyLe:
    #if depth > DepthLimit: raiseParseErr(p, "}")
    let res: PyDictObject = newPyDict() #newJObject()
    result = res
    discard getTok(p)
    while p.tok != tkCurlyRi:
      if p.tok != tkString:
        raiseParseErr(p, "string literal as key")
      var key = newPyStr p.a
      discard getTok(p)
      eat(p, tkColon)
      let val = p.parseJsonAsPy #parseJson(p, rawIntegers, rawFloats, depth+1)
      res[key] = val
      if p.tok != tkComma: break
      discard getTok(p)
    eat(p, tkCurlyRi)
  of tkBracketLe:
    #if depth > DepthLimit: raiseParseErr(p, "]")
    let res: PyListObject = newPyList() #newJArray()
    result = res
    discard getTok(p)
    while p.tok != tkBracketRi:
      res.add(p.parseJsonAsPy) #parseJson(p, rawIntegers, rawFloats, depth+1))
      if p.tok != tkComma: break
      discard getTok(p)
    eat(p, tkBracketRi)
  of tkError, tkCurlyRi, tkBracketRi, tkColon, tkComma, tkEof:
    raiseParseErr(p, "{")

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
  try:
    var p: JsonParser = default(JsonParser)
    p.open(s, filename)
    try:
      discard getTok(p) # read first token
      result = p.parseJsonAsPy #parseJson(p, rawIntegers, rawFloats, 0)
      eat(p, tkEof) # check if there is no extra data
    finally:
      p.close()
  except JsonParsingError as exc:
    return newValueError newPyAscii(exc.msg)
  except IOError as exc: return newValueError newPyAscii(exc.msg)
  except OSError as exc: return newValueError newPyAscii(exc.msg)
  except ValueError as exc:
    return newValueError newPyAscii(exc.msg)

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
