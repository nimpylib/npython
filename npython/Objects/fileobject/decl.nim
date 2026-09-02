
include ./comm
import ../[pyobject,]

declarePyType File():
  io: pyio.IOBase

proc newPyFile*(io: pyio.IOBase): PyFileObject =
  result = newPyFileSimple()
  result.io = io

