
import ../stringobject
import ./sub
proc newIOError*(e: ref IOError): PyIOErrorObject =
  newIOError newPyAscii e.msg

template handleIOErrRetPyObj*(body): untyped =
  bind newIOError
  try:
    body
  except IOError as e:
    return newIOError e
