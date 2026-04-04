
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

template implFormatValue*(T, impl){.dirty.} =
  bind handleValueErrorAsPyFormatExc
  proc formatValue*(res: var string, self: `Py T Object`; format_spec: static[string] = ""){.raises: [FormatPyObjectError].} =
    impl(res, self, format_spec)
  proc formatValue*(res: var string, self: `Py T Object`; format_spec: string) =
    handleValueErrorAsPyFormatExc:
      impl(res, self, format_spec)

template bindFormatValue*(T, selfToNimType){.dirty.} =
  bind implFormatValue
  template impl(res, self, format_spec) =
    res.formatValue(selfToNimType, format_spec)
  implFormatValue T, impl

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

