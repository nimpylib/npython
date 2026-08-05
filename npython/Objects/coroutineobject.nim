import pyobject
import frameobject

declarePyType Coroutine():
  frame: PyFrameObject
  finished: bool
  running: bool

proc newPyCoroutine*(frame: PyFrameObject): PyCoroutineObject =
  result = newPyCoroutineSimple()
  result.frame = frame

