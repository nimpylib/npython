
import ../Objects/[
  #pyobjectBase,
  exceptions, stringobject,
]
import ../Utils/compat

proc PyErr_BadArgument*: PyTypeErrorObject =
  newTypeError newPyAscii"bad argument type for built-in operation"

proc PyErr_FormatUnraisable*(msg: PyStrObject){.raises: [].} =
  #TODO:sys.unraisablehook
  errEchoCompatNoRaise $msg

