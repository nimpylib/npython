import pyobject


declarePyType Cell(tpToken):
  refObj{.member"cell_contents", nil2none.}: PyObject # might be nil

proc newPyCell*(content: PyObject): PyCellObject = 
  result = newPyCellSimple()
  result.refObj = content
