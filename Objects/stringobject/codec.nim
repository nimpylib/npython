
import ../[pyobjectBase,
  stringobject, exceptions,
  byteobjects,
  ]
import ./meth
import ../../Modules/posixmodule/utils

proc PyUnicode_DecodeFSDefault*(s: string): PyStrObject =
  #TODO:decode
  newPyStr s

proc PyUnicode_FSDecoder*(arg: PyObject, val: var PyStrObject): PyBaseErrorObject =
  let path = PyOS_FSPath(arg)
  retIfExc path
  let output = if path.ofPyStrObject: PyStrObject path
  elif path.ofPyBytesObject:
    PyUnicode_DecodeFSDefault PyBytesObject(path).items
  else:
    return newTypeError newPyStr(
      "path should be string, bytes, or os.PathLike, not " & arg.typeName.substr(0, 199))

  if output.find('\0') > 0:
    return newValueError newPyAscii"embedded null character"
  val = output
