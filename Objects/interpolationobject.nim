
import ./[
  bltcommon,
  pyobject,
  noneobject,
  exceptions,
  stringobject,
]
import ./stringobject/strformat
import ../Include/ceval

declarePyType Interpolation():
  value{.member.}: PyObject
  expression{.member.}: PyObject
  conversion{.member.}: PyObject
  format_spec{.member.}: PyObject

proc newPyInterpolationImpl(value, expression, format_spec: PyObject): PyInterpolationObject =
  let res = newPyInterpolationSimple()
  res.value = value
  res.expression = expression
  #res.conversion = conversion
  res.format_spec = format_spec
  return res

implInterpolationMagic New(typ,
    value, expression, conversion, format_spec):
  assert typ == pyInterpolationObjectType
  let res = newPyInterpolationImpl(value, expression, format_spec)
  res.conversion = conversion
  return res

implInterpolationMagic repr:
  template asgn(attr) =
    let `attr obj` = self.attr
    retIfExc `attr obj`
    let attr = $ `attr obj`
  asgn value
  asgn expression
  asgn conversion
  asgn format_spec
  newPyStr &"{self.typeName}({value}, {expression}, {conversion}, {format_spec})"

proc newPyInterpolation*(
  value, str: PyObject,
  conversion: PyFormatValueCode,
  format_spec: PyObject
): PyInterpolationObject =
  let res = newPyInterpolationImpl(value, str, format_spec)
  res.conversion =
      case conversion
      of FVC_NONE: pyNone
      of FVC_ASCII: newPyAscii 'a'
      of FVC_REPR: newPyAscii 'r'
      of FVC_STR: newPyAscii 's'
  result = res


proc newPyInterpolation*(
  value, str: PyObject,
  conversion: int,
  format_spec: PyObject
): PyObject =
  let res = newPyInterpolationImpl(value, str, format_spec)
  res.conversion =
    if conversion == 0: pyNone
    else:
      case conversion
      of ord FVC_ASCII: newPyAscii 'a'
      of ord FVC_REPR: newPyAscii 'r'
      of ord FVC_STR: newPyAscii 's'
      else:
        return newSystemError newPyAscii(
          block:
            var res = "Interpolation() argument 'conversion' must be one of 's', 'a' or 'r'"
            when defined(debug_interpolation):
              res.add(" (got " & $conversion & ")")
            res
        )
  result = res

