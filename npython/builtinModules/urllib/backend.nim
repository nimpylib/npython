import ./common
when defined(nimPreviewSlimSystem):
  import std/assertions

when defined(js):
  import std/jsfetch

  type ResponseTransport* = object

  proc retainTransport*(transport: var ResponseTransport): int = 0

  proc readTransport*(id, amt: int, content: var string)
      {.raises: [OSError, IOError].} =
    raise newException(OSError,
      "urllib.request.urlopen is synchronous; use an async JS bridge for fetch")

  proc closeTransport*(id: var int) {.raises: [LibraryError].} =
    id = 0

  proc requestHttp*(url, httpMethod, body: string,
      headers: openArray[(string, string)]; status: var int,
      reason: var string, responseUrl: var string,
      responseHeaders: var seq[(string, string)]; transport: var ResponseTransport
      ) {.raises: [OSError, IOError, ValueError].} =
    ## `std/jsfetch` is Promise-based and cannot implement synchronous `urlopen`.
    discard fetch(url.cstring)
    raise newException(OSError,
      "urllib.request.urlopen is synchronous; use an async JS bridge for fetch")
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
