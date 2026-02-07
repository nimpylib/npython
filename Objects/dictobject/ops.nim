
from std/sugar import collect
import std/tables
import ../[
  pyobject, exceptions,
  stringobject,
  noneobject,

]
import ../hash
export hash
import ../../Utils/[utils, optres]
import ./[decl, helpers]
export decl

template len*(self: PyDictObject): int = self.table.len

proc newPyDict*[K: PyObject, V: PyObject](table: sink Table[K, V]
): PyDictObject =
  result = newPyDictSimple()
  result.table = cast[Table[PyObject, PyObject]](table)

proc newPyDict*() : PyDictObject = newPyDict initTable[PyObject, PyObject]()

proc newPyDict*[V: PyObject](table: openArray[(PyObject, V)]): PyDictObject{.
    raises: [DictError].} =
  newPyDict table.toTable

proc newPyDict*[V: PyObject](table: openArray[(PyStrObject, V)]): PyDictObject{.
    raises: [].} =
  DictError!(block:
    newPyDict: collect:
      for (k, v) in table:
        {PyObject k: v}
  )

proc hasKey*(dict: PyDictObject, key: PyObject): bool =
  ## may raises DictError where Python raises TypeError
  dict.table.hasKey(key)
proc hasKey*(dict: PyDictObject, key: PyStrObject): bool = DictError!dict.hasKey(PyObject key)
proc contains*(dict: PyDictObject, key: PyObject): bool =
  ## may raises DictError where Python raises TypeError
  dict.hasKey key


proc `[]`*(dict: PyDictObject, key: PyObject): PyObject = dict.table[key]
type PyDictUnderlyingType = typeof((var x: PyDictObject; x.table))
proc `[]`*(dict: PyDictUnderlyingType, key: PyStrObject): PyObject = DictError!dict[PyObject key]
proc `[]`*(dict: PyDictObject, key: PyStrObject): PyObject = dict.table[key]

proc del*(dict: PyDictObject, key: PyObject) =
  ## do nothing if key not exists
  dict.table.del key

proc clear*(dict: PyDictObject) = dict.table.clear

proc `[]=`*(dict: PyDictObject, key, value: PyObject) = dict.table[key] = value
proc `[]=`*(dict: var PyDictUnderlyingType, key: PyStrObject, value: PyObject){.gcSafe, raises: [].} =
  {.gcSafe.}: DictError!!(dict[PyObject key] = value)
proc `[]=`*(dict: PyDictObject, key: PyStrObject, value: PyObject) = dict.table[key] = value

proc `==`*(dict1, dict2: PyDictObject): bool{.pyCFuncPragma.} =
  DictError!!(dict1.table == dict2.table)
# TODO: overload all bltin types and other functions?
template withValue*(dict: PyDictObject, key: PyStrObject; value; body) =
  ## we know `str.__eq__` and `str.__hash__` never raises
  DictError!!
    dict.table.withValue(key, value, body)
  
template withValue*(dict: PyDictObject, key: PyStrObject; value; body, elseBody) =
  ## we know `str.__eq__` and `str.__hash__` never raises
  DictError!!
    dict.table.withValue(key, value, body, elseBody)


template withValue*(dict: PyDictObject, key: PyObject; value; body) =
  ## `return` exception if error occurs on calling `__hash__` or `__eq__`
  bind withValue, handleHashExc
  handleHashExc:
    dict.table.withValue(key, value): body
template withValue*(dict: PyDictObject, key: PyObject; value; body, elseBody) =
  ## `return` exception if error occurs on calling `__hash__` or `__eq__`
  bind withValue, handleHashExc
  handleHashExc:
    dict.table.withValue(key, value, body, elseBody)



proc getItem*(dict: PyDictObject, key: PyObject): PyObject =
  ## unlike PyDict_GetItem (which suppresses all errors for historical reasons),
  ## returns KeyError if missing `key`, TypeError if `key` unhashable
  dict.withValue(key, value):
    return value[]
  do:
    return keyError key


proc getItemRef*(dict: PyDictObject, key: PyObject, res: var PyObject, exc: var PyBaseErrorObject): GetItemRes =
  ## `PyDict_GetItemRef`:
  ## if `key` missing, set res to nil
  result = GetItemRes.Error
  exc.handleBadHash:
    dict.table.withValue(key, value):
      res = value[]
      result = GetItemRes.Get
    do:
      res = nil
      result = GetItemRes.Missing

proc getItemRef*(dict: PyDictObject, key: PyStrObject, res: var PyObject): bool =
  ## PyDict_GetItemStringRef
  var exc: PyBaseErrorObject
  exc.handleBadHash:
    dict.table.withValue(key, value):
      res = value[]
      result = true
    do:
      res = nil
  assert exc.isNil, $exc

proc getOptionalItem*(dict: PyDictObject; key: PyObject): PyObject =
  ## like PyDict_GetItemWithError, can be used as `PyMapping_GetOptionalItem`:
  ##   returns nil if missing `key`, TypeError if `key` unhashable
  var exc: PyBaseErrorObject
  let res = dict.getItemRef(key, result, exc)
  case res
  of Get: discard
  of Missing: result = nil
  of Error: result = exc


proc setDefaultRef*(self: PyDictObject, key, defVal: PyObject; res: var PyObject): GetItemRes =
  result = GetItemRes.Error
  var exc: PyBaseErrorObject  # unused
  exc.handleBadHash:
    self.table.withValue(key, value):
      res = value[]
      result = GetItemRes.Get
    do:
      self[key] = defVal
      res = defVal
      result = GetItemRes.Missing

proc setDefaultRef*(self: PyDictObject, key, defVal: PyObject): GetItemRes =
  ## `PyDict_SetDefaultRef(..., NULL)`
  result = GetItemRes.Error
  if self.contains(key):
    result = GetItemRes.Get
  else:
    self[key] = defVal
    result = GetItemRes.Missing
proc setDefaultRef*(self: PyDictObject, key: PyStrObject, defVal: PyObject): GetItemRes = DictError!self.setDefaultRef(PyObject key, defVal)

proc setdefault*(self: PyDictObject, key: PyObject, defVal: PyObject = pyNone): PyObject =
  self.withValue(key, value):
    return value[]
  do:
    self[key] = defVal
    return defval
