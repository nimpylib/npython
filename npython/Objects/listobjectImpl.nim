
import ./[
  pyobject,
  listobject,
]
export listobject

import ../Utils/trans_imp
impExpCwd listobject, [
  bltin_sort, sort,
]

methodMacroTmpl(List)
registerBltinMethod pyListObjectType, "sort", builtin_sort
