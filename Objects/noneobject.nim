import pyobject
import ./stringobject

declarePyType None(tpToken):
  discard

let pyNone* = newPyNoneSimple()  ## singleton

proc isPyNone*(o: PyObject): bool = o == pyNone

const sNone = "None"
method `$`*(_: PyNoneObject): string = sNone

implNoneMagic repr: newPyAscii sNone

