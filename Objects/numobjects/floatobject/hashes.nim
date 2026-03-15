
import ../../pyobjectBase
import ./decl
import pkg/float_utils/hashes
import ../../hash
export Hash
proc hash*(self: PyFloatObject): Hash =
  try: hash(self.v)
  except ValueError: rawHash self

proc Py_HashDouble*(self: PyObject, v:float): Hash =
  ## `_Py_HashDouble`
  try: hash(v)
  except ValueError: rawHash self
