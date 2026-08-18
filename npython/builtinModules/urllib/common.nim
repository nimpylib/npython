import ../../Objects/[
  pyobject,
  moduleobjectImpl,
  exceptionsImpl,
  stringobject,
  byteobjects,
  dictobject,
  noneobject,
]

const
  urllibModuleName* = "urllib"
  urllibRequestModuleName* = "urllib.request"
  defaultHttpMethod* = "GET"
  headerSeparator* = ": "

declarePyType urllibModule(base(Module)):
  request{.member.}: PyObject

declarePyType urllibRequestModule(base(Module)):
  Request{.member.}: PyObject
  HTTPResponse{.member.}: PyObject

declarePyType Request():
  full_url{.member.}: PyStrObject
  data{.member, nil2none.}: PyObject
  headers{.member.}: PyDictObject
  request_method{.member"method", nil2none.}: PyObject

declarePyType HTTPResponse():
  transport_id: int
  url{.member.}: PyStrObject
  status{.member.}: int
  code{.member.}: int
  reason{.member.}: PyStrObject
  headers{.member.}: PyDictObject

proc headerName*(name: string): PyStrObject = newPyStr(name)

proc requireHeaderStrings*(headers: PyDictObject,
    output: var seq[(string, string)]): PyObject =
  for key, value in headers.pairs:
    if not key.ofPyStrObject or not value.ofPyStrObject:
      return newTypeError newPyAscii("headers must contain only str keys and values")
    output.add ($PyStrObject(key), $PyStrObject(value))
  pyNone

proc requestBody*(data: PyObject, body: var string): PyObject =
  if data.isPyNone:
    return pyNone
  if data.ofPyBytesObject:
    body = PyBytesObject(data).asString
  elif data.ofPyByteArrayObject:
    body = PyByteArrayObject(data).asString
  else:
    return newTypeError newPyAscii("POST data should be bytes or an iterable of bytes")
  pyNone

proc requestMethod*(request: PyRequestObject): string =
  if request.request_method.isNil or request.request_method.isPyNone:
    defaultHttpMethod
  else:
    $PyStrObject(request.request_method)
