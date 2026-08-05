import pyobject
import ./stringobject

declarePyType None(tpToken, singleton):
  discard

let pyNone* = newPyNoneSimple()  ## singleton
let pyNoneObj* = PyObject pyNone ##
## mainly for using as defval in  clinic gen signature

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

