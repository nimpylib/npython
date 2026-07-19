import pyobject
import frameobject

declarePyType Generator():
  frame: PyFrameObject
  finished: bool

proc newPyGenerator*(frame: PyFrameObject): PyGeneratorObject =
  result = newPyGeneratorSimple()
  result.frame = frame
