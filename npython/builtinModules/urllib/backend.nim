import ./common
when defined(nimPreviewSlimSystem):
  import std/assertions

when defined(js):
  import std/strutils
  import pysubprocess

  type
    ResponseTransport* = object
      content: string
      offset: int

  var transports: seq[ResponseTransport]

  proc retainTransport*(transport: var ResponseTransport): int =
    transports.add move transport
    transports.len

  proc readTransport*(id, amt: int, content: var string)
      {.raises: [OSError, IOError].} =
    if id <= 0 or id > transports.len:
      return
    let index = id - 1
    if transports[index].offset >= transports[index].content.len:
      return
    let remaining = transports[index].content.len - transports[index].offset
    let length = if amt < 0: remaining else: min(amt, remaining)
    content = transports[index].content[transports[index].offset ..<
      transports[index].offset + length]
    transports[index].offset.inc length

  proc closeTransport*(id: var int) {.raises: [LibraryError].} =
    if id > 0 and id <= transports.len:
      transports[id - 1] = default(ResponseTransport)
    id = 0

  proc findHeaderEnd(response: string, start: int): int =
    let crlfEnd = response.find("\r\n\r\n", start)
    if crlfEnd >= 0: crlfEnd + 4
    else:
      let lfEnd = response.find("\n\n", start)
      if lfEnd < 0: -1 else: lfEnd + 2

  proc parseCurlResponse(response: string, status: var int, reason: var string,
      responseHeaders: var seq[(string, string)], transport: var ResponseTransport)
      {.raises: [ValueError].} =
    var headerStart = 0
    var bodyStart = findHeaderEnd(response, headerStart)
    while bodyStart >= 0 and bodyStart + "HTTP/".len <= response.len and
        response[bodyStart ..< bodyStart + "HTTP/".len] == "HTTP/":
      headerStart = bodyStart
      bodyStart = findHeaderEnd(response, headerStart)
    if bodyStart < 0:
      raise newException(ValueError, "curl returned an invalid HTTP response")
    let lines = response[headerStart ..< bodyStart].splitLines()
    if lines.len == 0:
      raise newException(ValueError, "curl returned an empty HTTP response")
    let statusParts = lines[0].splitWhitespace()
    if statusParts.len < 2:
      raise newException(ValueError, "curl returned an invalid HTTP status")
    try:
      status = parseInt(statusParts[1])
    except ValueError:
      raise newException(ValueError, "curl returned an invalid HTTP status")
    reason = if statusParts.len > 2: statusParts[2 .. ^1].join(" ") else: ""
    if lines.len > 1:
      for line in lines[1 .. ^1]:
        let separator = line.find(':')
        if separator > 0:
          responseHeaders.add (line[0 ..< separator], line[separator + 1 .. ^1].strip())
    transport.content = response[bodyStart .. ^1]

  proc requestHttp*(url, httpMethod, body: string,
      headers: openArray[(string, string)]; status: var int,
      reason: var string, responseUrl: var string,
      responseHeaders: var seq[(string, string)]; transport: var ResponseTransport
      ) {.raises: [OSError, IOError, ValueError].} =
    var args = @["curl", "--silent", "--show-error", "--location",
      "--request", httpMethod, "--dump-header", "-", "--output", "-"]
    for (name, value) in headers:
      args.add "--header"
      args.add name & ": " & value
    if body.len > 0:
      args.add "--data-binary"
      args.add body
    args.add "--"
    args.add url
    var completed: CompletedProcess
    try:
      completed = run(args, captureOutput = true)
    except CalledProcessError as error:
      raise newException(OSError, error.msg)
    except TimeoutExpired as error:
      raise newException(OSError, error.msg)
    if completed.returncode != 0:
      raise newException(OSError, completed.stderr)
    parseCurlResponse(completed.stdout, status, reason, responseHeaders, transport)
    responseUrl = url
else:
  {.define: ssl.}
  import std/[httpclient, httpcore, net, streams, tables]

  type ResponseTransport* = object
    client*: HttpClient
    stream*: Stream

  var transports: Table[int, ResponseTransport]
  var nextTransportId = 1

  proc retainTransport*(transport: var ResponseTransport): int =
    result = nextTransportId
    inc nextTransportId
    transports[result] = move transport

  proc readTransport*(id, amt: int, content: var string)
      {.raises: [OSError, IOError].} =
    if id == 0 or not transports.hasKey(id):
      return
    let stream = transports.getOrDefault(id).stream
    if stream.isNil:
      return
    content = if amt < 0: stream.readAll() else: stream.readStr(amt)

  proc closeTransport*(id: var int) {.raises: [LibraryError].} =
    if id == 0 or not transports.hasKey(id):
      id = 0
      return
    let transport = transports.getOrDefault(id)
    transports.del(id)
    id = 0
    if transport.client.isNil:
      return
    try:
      transport.client.close()
    except LibraryError:
      raise
    except Exception as error:
      ## `HttpClient.close()` has the same unannotated OpenSSL load edge.
      raise cast[ref LibraryError](error)

  proc requestHttp*(url, httpMethod, body: string,
      headers: openArray[(string, string)]; status: var int,
      reason: var string, responseUrl: var string,
      responseHeaders: var seq[(string, string)]; transport: var ResponseTransport
      ) {.raises: [OSError, IOError, ValueError].} =
    var requestHeaders = newHttpHeaders()
    for (name, value) in headers:
      requestHeaders[name] = value
    var client: HttpClient
    var completed = false
    try:
      client = newHttpClient()
      try:
        let response = client.request(url, httpMethod, body, requestHeaders)
        status = int(response.code)
        reason = response.status
        responseUrl = url
        for name, value in response.headers.pairs:
          responseHeaders.add (name, value)
        transport.client = client
        transport.stream = response.bodyStream
        completed = true
      finally:
        if not completed and not client.isNil:
          client.close()
    except TimeoutError as e:
      raise newException(OSError, e.msg)
    except LibraryError as e:
      raise newException(OSError, e.msg)
    except SslError as e:
      raise newException(OSError, e.msg)
    except ProtocolError as e:
      raise newException(OSError, e.msg)
    except HttpRequestError as e:
      raise newException(OSError, e.msg)
    except OSError:
      raise
    except ValueError:
      raise
    except IOError:
      raise
    except Exception as error:
      ## Nim 2.2.8 does not annotate dynamic OpenSSL loading in the
      ## `httpclient` request path. Its concrete error is `LibraryError`.
      raise cast[ref LibraryError](error)
