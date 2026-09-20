
import ../../[
  pyobject,
]
type PyNimSequence = concept self
  self.items is seq[PyObject]

template PyNimSequence_Check*(o: PyObject): bool =
  bind PyNimSequence
  o is PyNimSequence
template ifPyNimSequence_Check*(o: PyObject, body) =
  when PyNimSequence_Check(o): body
template ifPyNimSequence_Check*(o: PyObject, body, elseDo): untyped =
  when PyNimSequence_Check(o): body
  else: elseDo

template PySequence_Check*(o: PyObject): bool =
  not o.getMagic(getitem).isNil

template ofPySequence*(o: PyObject): bool =
  ## PySequence_Check
  bind PySequence_Check
  PySequence_Check o
