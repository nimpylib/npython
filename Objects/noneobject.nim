import pyobject
import ./stringobject

declarePyType None(tpToken):
  discard

let pyNone* = newPyNoneSimple()  ## singleton

proc isPyNone*(o: PyObject): bool = o == pyNone

proc nil2none*(x: PyObject): PyObject =
  if x.isNil: pyNone
  else: x

proc none2nil*(x: PyObject): PyObject =
  if x.isPyNone: PyObject(nil)
  else: x

const sNone = "None"
method `$`*(_: PyNoneObject): string = sNone

implNoneMagic repr: newPyAscii sNone

