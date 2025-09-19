
import ./[
  pyobject,
  listobject,
]
export listobject

import ../Utils/trans_imp
impExp listobject,
  bltin_sort

methodMacroTmpl(List)
registerBltinMethod pyListObjectType, "sort", builtin_sort
