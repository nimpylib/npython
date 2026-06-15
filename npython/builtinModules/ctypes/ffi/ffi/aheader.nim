# to be included.
#   here exists the forware declaration to enforce function signature.
include ./comm

template implDynCall(body) {.dirty.} =
  proc callFunction*(self: PyCFuncObject, args: openArray[PyObject], kwargs: PyObject): PyObject{.raises: [].} =
    if not kwargs.isNil:
      return newTypeError newPyAscii"keyword arguments are not implemented yet"
    if self.handle.isNil:
      return newAttributeError(self.dll, self.name)
    body
