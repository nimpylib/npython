
import std/options
from std/strutils import `%`
import ../Utils/utils
import ./[
  pyobject,
  stringobject,
  numobjects,
  exceptions,
  noneobject,
]

declarePyType Warning(base(Exception)): discard

declarePyType WarningMessage():
  message: PyStrObject #PyStrObject
  category: PyObject #Warning
  filename: PyStrObject #PyStrObject
  lineno: PyIntObject #PyIntObject
  file: PyObject
  line: PyObject #Option PyStrObject
  source: PyObject
  private_category_name: Option[string]

proc newPyWarningMessage*(
    message: PyStrObject, category: PyTypeObject, filename: PyStrObject, lineno: PyIntObject,
    file: PyObject = pyNone, line: PyObject = pyNone, source: PyObject = pyNone
  ): PyWarningMessageObject =
  ## Create a new `WarningMessage` object.
  let self = newPyWarningMessageSimple()
  self.message = message
  self.category = category
  self.filename = filename
  self.lineno = lineno
  self.file = file
  self.line = line
  self.source = source
  self.private_category_name =
    if category.ofPyNoneObject: none(string)
    else: some(category.name)
  result = self

proc categoryName*(self: PyWarningMessageObject): string =
  ## Get the name of the warning category.
  if self.private_category_name.isSome:
    self.private_category_name.unsafeGet
  else: "None"

#[
implWarningMessageMagic init:
  # (message, category, filename, lineno: PyObject,
  # file, line, source: PyObject = pyNone):
  if args.len < 3 or args.len > 7:
    return newTypeError(  # Fixed typo from 'retun' to 'return'
      "WarningMessage.__init__() takes 3 to 7 positional arguments but $# were given" % $args.len)
  else:  # Added else to handle the case when the argument count is valid
    template nArgOrNone(n): PyObject =
      if args.len > n: args[n] else: pyNone
    newPyWarningMessage(args[0],
      args[1],
      args[2],
      args[3],
      nArgOrNone(4),
      nArgOrNone(5),
      nArgOrNone(6),
    )
]#

template callReprOrStr(obj: PyObject, reprOrStr): string =
  $obj.getMagic(reprOrStr)(obj).PyStrObject.str

proc `$`*(self: PyWarningMessageObject): string{.raises: [].} =
  ValueError!(
    ("{message : $#, category : $#, filename : $#, lineno : $#, " &
            "line : $#}") % [self.message.callReprOrStr(repr), self.categoryName,
                            self.filename.callReprOrStr(repr), self.lineno.callReprOrStr(str), self.line.callReprOrStr(repr)]
  )

implWarningMessageMagic str:
  newPyStr $self

template declWarning(w){.dirty.} =
  declarePyType w(base(Warning)): discard

declWarning SyntaxWarning

declWarning DeprecationWarning
declWarning PendingDeprecationWarning

declWarning ImportWarning
declWarning ResourceWarning

declWarning RuntimeWarning
