
import ../pyobjectBase
template PySequence_Check*(o: PyObject): bool =
  ## PY-DIFF: we check whether o has items: seq[PyObject]
  when not compiles(o.items): false
  else: o.items is seq[PyObject]
template ifPySequence_Check*(o: PyObject, body) =
  when PySequence_Check(o): body
template ifPySequence_Check*(o: PyObject, body, elseDo): untyped =
  when PySequence_Check(o): body
  else: elseDo
