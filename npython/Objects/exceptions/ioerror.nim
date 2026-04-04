
import ../stringobject
import ./sub
proc newIOError*(e: ref IOError): PyIOErrorObject =
  newIOError newPyAscii e.msg
