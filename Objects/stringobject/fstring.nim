
import ./strformat
export strformat
import ../[
  pyobject,
  stringobject,
  exceptions,
  bltcommon,
]

template handleValueErrorAsPyFormatExc*(body) =
  bind raisePyFormatExc, newValueError, newPyStr 
  try:
    body
  except ValueError as e:
    raisePyFormatExc newValueError newPyStr e.msg

template bindFormatValue*(T, selfToNimType){.dirty.} =
  bind handleValueErrorAsPyFormatExc
  proc formatValue*(res: var string, self: `Py T Object`; format_spec = "") =
    handleValueErrorAsPyFormatExc:
      res.formatValue(selfToNimType, format_spec)

template genFormat*(T){.dirty.} =
  bind handleFormatExc

  `impl T Method` "__format__"(format_spec: PyStrObject):
    var res: string
    handleFormatExc:
      try:
        res.formatValue(self, $format_spec.str)
      except ValueError as e:
        return newValueError newPyStr e.msg
    result = newPyStr res

methodMacroTmpl(str)
bindFormatValue str, $self.str
genFormat str

