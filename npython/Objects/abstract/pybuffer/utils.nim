
import ../../pyobject

proc ofPyBuffer*(obj: PyObject): bool =
  ## `PyObject_CheckBuffer`
  obj.getMagic(buffer).isNil.not
