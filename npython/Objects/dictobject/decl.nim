
import std/tables
import ../pyobject
# currently not ordered
# nim ordered table has O(n) delete time
# todo: implement an ordered dict 
declarePyType Dict(tpToken, reprLock, mutable):
  table: Table[PyObject, PyObject]
