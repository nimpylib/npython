import std/streams
import std/parsejson

from std/strutils import repeat, toHex, toLowerAscii

import ./private/[utils, gen]
import pkg/handy_sugars/trans_imp
import ./json/[
  dumpUtils, objFields,
]
impExpCwd json, [
  err,
]

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
impObjects exceptions/ioerror
impObjects exceptions/oserr/convert
impObjects abstract/call
imp Python, [call, getargs/kwargs, getargs/va_and_kw,
  getargs/vargs, getargs/topys]
import ../Objects/listobject/sort
import pkg/intobject

genModule json

template gen_var(nam, variable) {.dirty.} =
  genProperty JsonModule, astToStr(nam), nam: variable
gen_var JSONDecodeError, pyJSONDecodeErrorObjectType

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
proc parseConstant(name: string, default: float, opt: DecodeOptions): PyObject =
  if opt.parse_constant.isPyNone:
    return newPyFloat default
  opt.parse_constant.call(newPyAscii name)

proc parseJsonAsPy(p: var JsonParser, res: var PyObject,
                   opt: DecodeOptions): PyBaseErrorObject {.raises: [IOError, OSError].} =
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
      res = parseConstant("-Infinity", NegInf, opt)
      retIfExc res
      discard getTok(p)
    else:
      if opt.parse_int.isPyNone:
        try:
          res = newPyInt p.a
        except ValueError as e:
          return newValueError newPyAscii e.msg
      else:
        res = opt.parse_int.call(newPyAscii p.a)
        retIfExc res
      discard getTok(p)
  of tkFloat:
    if opt.parse_float.isPyNone:
      var fres: PyFloatObject
      let exc = PyFloat_FromString(newPyAscii p.a, fres)
      if not exc.isNil:
        p.retE PyStrObject exc.args[0]
      res = fres
    else:
      res = opt.parse_float.call(newPyAscii p.a)
      retIfExc res
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
    let pairs = newPyList()
    discard getTok(p)
    while p.tok != tkCurlyRi:
      if p.tok != tkString:
        p.retE newPyAscii "string literal as key"
      var key = newPyStr p.a
      discard getTok(p)
      myeat(p, tkColon)
      var val: PyObject
      retIfExc p.parseJsonAsPy(val, opt)
      resObj[key] = val
      pairs.add newPyTuple([PyObject key, val])
      if p.tok != tkComma: break
      discard getTok(p)
    myeat(p, tkCurlyRi)
    if not opt.object_pairs_hook.isPyNone:
      res = opt.object_pairs_hook.call(pairs)
      retIfExc res
    elif not opt.object_hook.isPyNone:
      res = opt.object_hook.call(resObj)
      retIfExc res
    else:
      res = resObj
  of tkBracketLe:
    #if depth > DepthLimit: raiseParseErr(p, "]")
    let resObj: PyListObject = newPyList() #newJArray()
    res = resObj
    discard getTok(p)
    while p.tok != tkBracketRi:
      var val: PyObject
      retIfExc p.parseJsonAsPy(val, opt)
      resObj.add(val) #parseJson(p, rawIntegers, rawFloats, depth+1))
      if p.tok != tkComma: break
      discard getTok(p)
    myeat(p, tkBracketRi)
  of tkError:
    case p.a
    of "NaN":
      res = parseConstant("NaN", NaN, opt)
    of "Infinity":
      res = parseConstant("Infinity", Inf, opt)
    # -Infinity is handled in tkInt case
    else:
      p.retE newPyAscii "invalid token"
    retIfExc res
    discard getTok(p)
  of tkCurlyRi, tkBracketRi, tkColon, tkComma, tkEof:
    p.retE newPyAscii "{" & " excepted"


proc toJsonString(obj: PyObject, output: var string, opt: EncodeOptions,
                  markers: var seq[PyObject], depth: int,
                  itemSeparator, keySeparator, indentUnit: string,
                  indented: bool): PyBaseErrorObject =
  if obj.isPyNone:
    output.add "null"
  elif obj.ofPyBoolObject:
    output.add(if PyBoolObject(obj).isPyTrue: "true" else: "false")
  elif obj.ofPyIntObject:
    output.add $PyIntObject(obj).v
  elif obj.ofPyFloatObject:
    retIfExc floatToken(PyFloatObject(obj).v, opt.allow_nan, output)
  elif obj.ofPyStrObject:
    output.add encodeString(PyStrObject(obj), opt.ensure_ascii)
  elif obj.ofPyListObject or obj.ofPyTupleObject:
    let markerCount = markers.len
    retIfExc pushMarker(obj, opt.check_circular, markers)
    output.add '['
    var first = true
    template addItem(item: PyObject) =
      if first:
        first = false
      else:
        output.add itemSeparator
      if indented:
        output.addIndent(indentUnit, depth + 1)
      let exc = toJsonString(item, output, opt, markers, depth + 1,
                             itemSeparator, keySeparator, indentUnit, indented)
      if not exc.isNil:
        markers.setLen markerCount
        return exc
    if obj.ofPyListObject:
      for item in PyListObject(obj):
        addItem item
    else:
      for item in PyTupleObject(obj):
        addItem item
    if indented and not first:
      output.addIndent(indentUnit, depth)
    output.add ']'
    markers.setLen markerCount
  elif obj.ofPyDictObject:
    let markerCount = markers.len
    retIfExc pushMarker(obj, opt.check_circular, markers)
    output.add '{'
    var first = true
    var keys = newPyList()
    for key in PyDictObject(obj).keys:
      keys.add key
    if opt.sort_keys:
      let exc = keys.sort()
      if not exc.isNil:
        markers.setLen markerCount
        return exc
    for key in keys:
      var encodedKey = ""
      let keyExc = encodeKey(key, opt, encodedKey)
      if not keyExc.isNil:
        markers.setLen markerCount
        return keyExc
      if encodedKey.len == 0:
        continue
      if first:
        first = false
      else:
        output.add itemSeparator
      if indented:
        output.addIndent(indentUnit, depth + 1)
      output.add encodedKey
      output.add keySeparator
      let value = PyDictObject(obj).getItem(key)
      if value.isThrownException:
        markers.setLen markerCount
        return PyBaseErrorObject value
      let valueExc = toJsonString(value, output, opt, markers, depth + 1,
                                  itemSeparator, keySeparator, indentUnit,
                                  indented)
      if not valueExc.isNil:
        markers.setLen markerCount
        return valueExc
    if indented and not first:
      output.addIndent(indentUnit, depth)
    output.add '}'
    markers.setLen markerCount
  else:
    if opt.default.isPyNone:
      return newTypeError newPyStr(
        "Object of type " & obj.typeName & " is not JSON serializable")
    let markerCount = markers.len
    retIfExc pushMarker(obj, opt.check_circular, markers)
    let replacement = opt.default.call(obj)
    if replacement.isThrownException:
      markers.setLen markerCount
      return PyBaseErrorObject replacement
    let exc = toJsonString(replacement, output, opt, markers, depth,
                           itemSeparator, keySeparator, indentUnit, indented)
    markers.setLen markerCount
    return exc

proc decodeJson(s: Stream, opt: DecodeOptions): PyObject =
  const filename = ""
  handleOsErrRetPyObj:
    try:
      var p: JsonParser = default(JsonParser)
      p.open(s, filename)
      try:
        discard getTok(p) # read first token
        retIfExc p.parseJsonAsPy(result, opt)
        myeat(p, tkEof) # check if there is no extra data
      finally:
        p.close()
    except IOError as exc: return newIOError exc

proc decodeJson(s: string, opt: DecodeOptions): PyObject =
  decodeJson(newStringStream(s), opt)

proc toString(s: openArray[char]): string =
  result = newStringUninit(s.len)
  for i, c in s: result[i] = c
proc decodeJson(s: openArray[char], opt: DecodeOptions): PyObject =
  decodeJson(toString(s), opt)

proc loads*(s: PyStrObject, opt: DecodeOptions): PyObject =
  decodeJson(s.asUTF8, opt)
proc loads*(s: PyBytesObject|PybytearrayObject, opt: DecodeOptions): PyObject =
  decodeJson(s.items, opt)

proc loads*(s: PyObject, opt: DecodeOptions): PyObject =
  if s.ofPyStrObject: loads(PyStrObject(s), opt)
  elif s.ofPyBytesObject: loads(PyBytesObject(s), opt)
  elif s.ofPyByteArrayObject: loads(PyByteArrayObject(s), opt)
  else:
    newTypeError newPyStr(
      "the JSON object must be str, bytes or bytearray, not " & s.typeName)

proc dumps*(obj: PyObject, opt: EncodeOptions): PyObject =
  var encoded = ""
  var markers: seq[PyObject]
  var itemSeparator, keySeparator, indentUnit: string
  var indented: bool
  retIfExc resolveFormatting(opt, itemSeparator, keySeparator,
                             indentUnit, indented)
  let exc = toJsonString(obj, encoded, opt, markers, 0,
                         itemSeparator, keySeparator, indentUnit, indented)
  retIfExc exc
  newPyStr encoded

template setKeyword[T](kwargs: PyDictObject, name: string, value: T,
                omitNone: static[bool] = false) =
  var valueObj: PyObject
  retIfExc toPy(value, valueObj)
  if not omitNone or not valueObj.isPyNone:
    kwargs[newPyStr name] = valueObj

proc unexpectedKeyword(funcName: string,
                       kwargs: PyDictObject): PyBaseErrorObject =
  if kwargs.isNil: return
  for key in kwargs.keys:
    return newTypeError newPyStr(
      funcName & "() got an unexpected keyword argument '" & $key & "'")


template loadsOrDumps(arg; loads; optT: typedesc; omitNoneArgs: bool,
    clsMeth: string): untyped =
  if not cls.isPyNone:
    let kwargs = if extraKeywords.isNil: newPyDict() else: extraKeywords
    forFields itS, it, optT:
      kwargs.setKeyword(itS, it, omitNone = omitNoneArgs)
    let decoder = fastCall(cls, [], kwargs)
    retIfExc decoder
    return decoder.callMethod(newPyAscii(clsMeth), arg)

  retIfExc unexpectedKeyword(astToStr(loads), extraKeywords)
  let opt = initFromLocals optT
  loads(arg, opt)

{.push warning[ImplicitDefaultValue]: off.}
proc loads*(s: PyObject,
    cls, objectHook, parseFloat, parseInt,
    parseConstant, objectPairsHook: PyObject = pyNone,
    extraKeywords: PyDictObject = nil): PyObject =
  loadsOrDumps s,
    loads, DecodeOptions, omitNoneArgs = true, clsMeth = "decode"

proc dumps*(obj: PyObject,
    skipkeys = false, ensureAscii = true, checkCircular = true,
    allowNan = true, cls, indent: PyObject = pyNone,
    separators = none Separators,
    default: PyObject, sortKeys = false,
    extraKeywords: PyDictObject = nil): PyObject =
  loadsOrDumps obj,
    dumps, EncodeOptions, omitNoneArgs = false, clsMeth = "encode"
{.pop.}

#TODO:io: load, dump
impljsonModuleMethod loads:
  let kw = PyDictObject kwargs

  retIfExc PyArg_ParseTupleAndKeywordsAs(
    "loads", args, kw,
    DecodeOptions.fieldNameArrayAdded("cls"),
    s: PyObject,
    cls = pyNoneObj,
    object_hook = pyNoneObj,
    parse_float = pyNoneObj,
    parse_int = pyNoneObj,
    parse_constant = pyNoneObj,
    object_pairs_hook = pyNoneObj,
    **extraKeywords)
  loads(s, cls, object_hook, parse_float, parse_int, parse_constant,
        object_pairs_hook, extraKeywords)

impljsonModuleMethod dumps:
  let kw = PyDictObject kwargs

  retIfExc PyArg_ParseTupleAndKeywordsAs(
    "dumps", args, kw,
    EncodeOptions.fieldNameArrayAdded("cls"),
    obj: PyObject,
    skipkeys = false,
    ensure_ascii = true,
    check_circular = true,
    allow_nan = true,
    cls = pyNoneObj,
    indent = pyNoneObj,
    separators = none Separators,
    default = pyNoneObj,
    sort_keys = false,
    **extraKeywords)
  dumps(obj, skipkeys, ensure_ascii, check_circular, allow_nan,
        cls, indent, separators, default, sort_keys, extraKeywords)
