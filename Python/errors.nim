
import ../Objects/[exceptions, stringobject]

proc PyErr_BadArgument*: PyTypeErrorObject =
  newTypeError newPyAscii"bad argument type for built-in operation"

