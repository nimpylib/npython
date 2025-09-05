import strformat


import tables
import macros

import pyobject 
# import listobject (do not import, or it'll cause recursive import)
import baseBundle
import ../Utils/[utils, optres]
export GetItemRes
import ./[iterobject, tupleobject]
from ./stringobject import PyStrObject
import ./hash
export hash

# currently not ordered
# nim ordered table has O(n) delete time
# todo: implement an ordered dict 
declarePyType Dict(tpToken, reprLock, mutable):
  table: Table[PyObject, PyObject]


proc newPyDict*(table=initTable[PyObject, PyObject]()) : PyDictObject = 
  result = newPyDictSimple()
  result.table = table
proc newPyDict*(table: openArray[(PyObject, PyObject)]) : PyDictObject = 
  newPyDict table.toTable

proc hasKey*(dict: PyDictObject, key: PyObject): bool =
  ## may raises DictError where Python raises TypeError
  dict.table.hasKey(key)
proc hasKey*(dict: PyDictObject, key: PyStrObject): bool = DictError!dict.hasKey(PyObject key)
proc contains*(dict: PyDictObject, key: PyObject): bool =
  ## may raises DictError where Python raises TypeError
  dict.hasKey key

template borIter(name, nname; R=PyObject){.dirty.} =
  iterator name*(dict: PyDictObject): R =
    for i in dict.table.nname: yield i
template borIter(name){.dirty.} = borIter(name, name)

borIter items, keys
borIter keys
borIter values
borIter pairs, pairs, (PyObject, PyObject)

implDictMagic iter, [mutable: read]:
  genPyNimIteratorIter self.keys()
implDictMethod keys(), [mutable: read]:
  genPyNimIteratorIter self.keys()
implDictMethod values(), [mutable: read]:
  genPyNimIteratorIter self.values()

iterator pyItems(dict: PyDictObject): PyTupleObject =
  for (k, v) in dict.pairs:
    yield newPyTuple([k, v])
implDictMethod items(), [mutable: read]:
  genPyNimIteratorIter self.pyItems

proc `[]`*(dict: PyDictObject, key: PyObject): PyObject = dict.table[key]
proc `[]`*(dict: PyDictObject, key: PyStrObject): PyObject = DictError!dict[PyObject key]

proc del*(dict: PyDictObject, key: PyObject) =
  ## do nothing if key not exists
  dict.table.del key

proc clear*(dict: PyDictObject) = dict.table.clear

proc `[]=`*(dict: PyDictObject, key, value: PyObject) = dict.table[key] = value
proc `[]=`*(dict: PyDictObject, key: PyStrObject, value: PyObject) = DictError!!(dict[PyObject key] = value)

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

implDictMagic contains, [mutable: read]:
  var res: bool
  handleHashExc:
    res = self.table.hasKey(other)
  newPyBool(res)

implDictMagic repr, [mutable: read, reprLockWithMsg"{...}"]:
  var ss: seq[UnicodeVariant]
  for k, v in self.table.pairs:
    let kRepr = k.callMagic(repr)
    let vRepr = v.callMagic(repr)
    errorIfNotString(kRepr, "__str__")
    errorIfNotString(vRepr, "__str__")
    ss.add newUnicodeUnicodeVariant PyStrObject(kRepr).str.toRunes &
      toRunes": " &
      PyStrObject(vRepr).str.toRunes
  return newPyString(toRunes"{" & ss.joinAsRunes(", ") & toRunes"}")


implDictMagic len, [mutable: read]:
  newPyInt(self.table.len)

implDictMagic hash: unhashable self
implDictMagic eq:
  newPyBool(
    other.ofPyDictObject() and
    DictError!(self.table == other.PyDictObject.table)
  )
implDictMagic Or(E: PyDictObject), [mutable: read]:
  let res = newPyDict self.table
  DictError!(
    for (k, v) in E.table.pairs:
      res.table[k] = v
    res
  )

template keyError(other: PyObject): PyBaseErrorObject =
  let repr = other.pyType.magicMethods.repr(other)
  if repr.isThrownException:
    PyBaseErrorObject repr
  else:
    PyBaseErrorObject newKeyError PyStrObject(repr)

template handleBadHash(res; body){.dirty.} =
  template setRes(e) = res = e
  handleHashExc setRes:
    body

proc getItem*(dict: PyDictObject, key: PyObject): PyObject =
  ## unlike PyDict_GetItem (which suppresses all errors for historical reasons),
  ## returns KeyError if missing `key`, TypeError if `key` unhashable
  dict.withValue(key, value):
    return value[]
  do:
    return keyError key


proc getItemRef*(dict: PyDictObject, key: PyObject, res: var PyObject, exc: var PyBaseErrorObject): GetItemRes =
  ## `PyDict_GetItemRef`:
  ## if `key` missing, set res to nil and return KeyError
  result = GetItemRes.Error
  exc.handleBadHash:
    dict.table.withValue(key, value):
      res = value[]
      result = GetItemRes.Get
    do:
      res = nil
      exc = keyError key
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
      exc = keyError key
  assert exc.isNil

proc getOpionalItem*(dict: PyDictObject; key: PyObject): PyObject =
  ## like PyDict_GetItemWithError, can be used as `PyMapping_GetOptionalItem`:
  ##   returns nil if missing `key`, TypeError if `key` unhashable
  var exc: PyBaseErrorObject
  let res = dict.getItemRef(key, result, exc)
  case res
  of Get: discard
  of Missing: result = nil
  of Error: result = exc

implDictMagic getitem, [mutable: read]: self.getitem other

implDictMagic setitem, [mutable: write]:
  result.handleBadHash:
    self.table[arg1] = arg2
  pyNone

proc pop*(self: PyDictObject, other: PyObject, res: var PyObject): bool =
  ## returns true iff other in self (it means also returning false on exception)
  ##
  ## - if `other` not in `self`, `res` is set to KeyError;
  ## - if in, set to value of that key;
  ## - if exception raised, `res` is set to that
  res.handleBadHash:
    if self.table.pop(other, res):
      return true
  res = keyError other
  return false

proc delitemImpl*(self: PyDictObject, other: PyObject): PyObject =
  ## internal use. (in typeobject)
  if self.pop(other, result):
    return pyNone
  assert not result.isNil

implDictMagic delitem, [mutable: write]:
  self.delitemImpl other

implDictMethod get, [mutable: write]:
  checkargnumatleast 1
  let key = args[0]
  if args.len == 1:
    return self.getItem key
  checkargnum 2
  let defval = args[1]
  result.handleBadHash:
    return self.table.getOrDefault(key, defVal)

implDictMethod pop, [mutable: write]:
  checkargnumatleast 1
  let key = args[0]
  if args.len == 1:
    return self.delitemimpl key
  checkargnum 2
  let defval = args[1]
  if self.pop(key, result):
    return
  # XXX: Python's dict.pop(k, v) discard TypeError, KeyError
  return defval

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

implDictMethod setdefault, [mutable: write]:
  checkargnumatleast 1
  let key = args[0]
  let defVal = if args.len == 1: pyNone
  else:
    checkargnum 2
    args[1]
  self.setdefault(key, defVal)

implDictMethod clear(), [mutable: write]: self.clear()

implDictMethod copy(), [mutable: read]:
  let newT = newPyDict()
  newT.table = self.table
  newT

# in real python this would return a iterator
# this function is used internally


proc update*(d1, d2: PyDictObject) = 
  for k, v in d2.table.pairs:
    d1[k] = v

# .__init__, .update, .keys, etc method is defined in ./dictobjectImpl
