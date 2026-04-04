
import ../../Objects/[
  pyobjectBase,
  exceptions,
  stringobject,
  dictobject,
  listobject,
]
import ../../Objects/numobjects/intobject
export pyobjectBase, exceptions, stringobject, dictobject, listobject, intobject

template SET_SYSimpl(key; v) =
  retIfExc sysdict.setItem(newPyAscii key, v)
template SET_SYS*(key; value: PyIntObject|PyListObject|PyDictObject) = SET_SYSimpl(key, value)
template `!`*(value: PyObject): PyObject =
  bind retIfExc
  let v = value
  retIfExc v
  v
template SET_SYS*(key; value: PyObject) =
  bind `!`
  SET_SYSimpl(key, !value)
template SET_SYS*(key; value: string) =
  ## SET_SYS_FROM_STRING
  SET_SYSimpl(key, newPyStr(value))
