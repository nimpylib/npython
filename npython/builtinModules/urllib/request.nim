import ./[common, backend]
import ../private/utils
import ../../Objects/[pyobject, stringobject, byteobjects, dictobject,
  noneobject, boolobjectImpl, numobjects, moduleobjectImpl, exceptionsImpl]
import ../../Objects/pyobject_apis/attrs
import ../../Python/getargs/dispatch
import ../../Python/getargs/paramsMeta
import ../../Python/getargs/va_and_kw

methodMacroTmpl(urllibRequestModule)
methodMacroTmpl(Request)
methodMacroTmpl(HTTPResponse)

proc makeRequest*(url: string, data: PyObject = pyNoneObj,
    headers: PyDictObject = nil, originReqHost: PyObject = pyNoneObj,
    unverifiable = false, `method`: PyObject = pyNoneObj): PyObject =
  if not `method`.isPyNone and not `method`.ofPyStrObject:
    return newTypeError newPyAscii("method must be a string")
  let resultRequest = newPyRequestSimple()
  resultRequest.full_url = newPyStr url
  resultRequest.data = data
  resultRequest.headers = if headers.isNil: newPyDict() else: headers
  resultRequest.request_method = `method`
  resultRequest

implRequestMagic init:
  let kw = PyDictObject kwargs
  retIfExc PyArg_ParseTupleAndKeywordsAs(
    "Request", args, kw,
    ["data", "headers", "origin_req_host", "unverifiable", "method"],
    url: string,
    data = pyNoneObj,
    headers = pyNoneObj,
    origin_req_host = pyNoneObj,
    unverifiable = false,
    request_method {.AsPyParam("method").} = pyNoneObj)
  let headerDict =
    if headers.isPyNone: PyDictObject nil
    elif headers.ofPyDictObject: PyDictObject headers
    else: return newTypeError newPyAscii("headers must be a dict")
  let initialized = makeRequest(url, data, headerDict, origin_req_host,
    unverifiable, request_method)
  retIfExc initialized
  let request = PyRequestObject initialized
  self.full_url = request.full_url
  self.data = request.data
  self.headers = request.headers
  self.request_method = request.request_method
  pyNone

implRequestMethod get_full_url(): self.full_url
implRequestMethod get_method(): newPyStr requestMethod(self)

implRequestMethod has_header(header_name: string):
  newPyBool self.headers.hasKey(headerName(header_name))

implRequestMethod get_header(header_name: string, default = pyNoneObj):
  let value = self.headers.getOptionalItem(headerName(header_name))
  if value.isNil: default else: value

implRequestMethod add_header(key: string, val: string):
  self.headers[headerName(key)] = newPyStr val
  pyNone

proc responseHeaders(headers: openArray[(string, string)]): PyDictObject =
  result = newPyDict(headers.len)
  for (name, value) in headers:
    result[headerName(name)] = newPyStr value

proc openRequest*(request: PyRequestObject): PyObject =
  var body: string
  retIfExc requestBody(request.data, body)
  var requestHeaders: seq[(string, string)]
  retIfExc requireHeaderStrings(request.headers, requestHeaders)
  var reason, responseUrl: string
  var status: int
  var headers: seq[(string, string)]
  var transport: ResponseTransport
  try:
    requestHttp($request.full_url, requestMethod(request), body, requestHeaders,
      status, reason, responseUrl, headers, transport)
  except OSError as e:
    return newOSError newPyAscii e.msg
  except IOError as e:
    return newOSError newPyAscii e.msg
  except ValueError as e:
    return newValueError newPyAscii e.msg
  let response = newPyHTTPResponseSimple()
  response.transport_id = retainTransport(transport)
  response.url = newPyStr responseUrl
  response.status = status
  response.code = status
  response.reason = newPyStr reason
  response.headers = responseHeaders(headers)
  response

proc urlopen*(url: PyObject, data: PyObject = pyNoneObj,
    timeout: PyObject = pyNoneObj): PyObject =
  let request =
    if url.ofPyRequestObject:
      PyRequestObject(url)
    elif url.ofPyStrObject:
      let created = makeRequest($PyStrObject(url), data)
      retIfExc created
      PyRequestObject(created)
    else:
      return newTypeError newPyAscii("urlopen() expected str or Request")
  openRequest request

proc read*(self: PyHTTPResponseObject, amt = -1): PyObject =
  try:
    var content: string
    readTransport(self.transport_id, amt, content)
    newPyBytes content
  except IOError as e:
    newOSError newPyAscii e.msg
  except OSError as e:
    newOSError newPyAscii e.msg

proc close*(self: PyHTTPResponseObject): PyObject =
  try:
    closeTransport(self.transport_id)
    pyNone
  except LibraryError as e:
    newOSError newPyAscii e.msg

implHTTPResponseMethod read(amt = -1): self.read(amt)
implHTTPResponseMethod close(): self.close()

implHTTPResponseMethod getcode(): newPyInt self.code
implHTTPResponseMethod geturl(): self.url
implHTTPResponseMagic enter: self
implHTTPResponseMagic exit(exc_type, exc, traceback):
  let closed = self.close()
  retIfExc closed
  pyFalseObj

proc PyInit_request*: PyObject =
  result = PyModule_CreateInitialized(urllibRequest)
  retIfExc result
  let module = PyurllibRequestModuleObject(result)
  module.Request = pyRequestObjectType
  module.HTTPResponse = pyHTTPResponseObjectType

implurllibRequestModuleMethod urlopen:
  let kw = PyDictObject kwargs
  retIfExc PyArg_ParseTupleAndKeywordsAs(
    "urlopen", args, kw, ["data", "timeout"],
    url: PyObject,
    data = pyNoneObj,
    timeout = pyNoneObj)
  urlopen(url, data, timeout)
