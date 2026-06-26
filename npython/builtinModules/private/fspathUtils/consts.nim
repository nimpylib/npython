

include ./comm
impObjects [
  stringobject,
]
proc cannotMixPathLikeError*: PyBaseErrorObject =
  newTypeError newPyAscii "Can't mix strings and bytes in path components"


proc shouldBePathLike3Error*(obj: PyObject, prefix="path"): PyBaseErrorObject =
  newTypeError newPyStr prefix & " should be string, bytes, or os.PathLike, not " & obj.typeName


