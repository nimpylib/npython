import strformat


import tables
import macros

import pyobject 
# import listobject (do not import, or it'll cause recursive import)
import baseBundle
import ../Utils/utils
import ./[iterobject, tupleobject]
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

proc hasKey*(dict: PyDictObject, key: PyObject): bool =
  return dict.table.hasKey(key)
proc contains*(dict: PyDictObject, key: PyObject): bool = dict.hasKey key

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

proc `[]`*(dict: PyDictObject, key: PyObject): PyObject = 
  return dict.table[key]

proc del*(dict: PyDictObject, key: PyObject) =
  ## do nothing if key not exists
  dict.table.del key

proc clear*(dict: PyDictObject) = dict.table.clear

proc `[]=`*(dict: PyDictObject, key, value: PyObject) = 
  dict.table[key] = value


template checkHashableTmpl(res; obj) =
  let hashFunc = obj.pyType.magicMethods.hash
  if hashFunc.isNil:
    let tpName = obj.pyType.name
    let msg = "unhashable type: " & tpName
    res = newTypeError newPyStr(msg)
    return

template checkHashableTmpl(obj) =
  result.checkHashableTmpl(obj)


implDictMagic contains, [mutable: read]:
  checkHashableTmpl(other)
  try:
    result = self.table.getOrDefault(other, nil)
  except DictError:
    let msg = "__hash__ method doesn't return an integer or __eq__ method doesn't return a bool"
    return newTypeError newPyAscii(msg)
  return newPyBool(not result.isNil)

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
    self.table == other.PyDictObject.table
  )
implDictMagic Or(E: PyDictObject), [mutable: read]:
  let res = newPyDict self.table
  for (k, v) in E.table.pairs:
    res.table[k] = v
  res

template keyError(other: PyObject): PyObject =
  var msg: PyStrObject
  let repr = other.pyType.magicMethods.repr(other)
  if repr.isThrownException:
    msg = newPyAscii"exception occured when generating key error msg calling repr"
  else:
    msg = PyStrObject(repr)
  newKeyError(msg)

let badHashMsg = 
  newPyAscii"__hash__ method doesn't return an integer or __eq__ method doesn't return a bool"

template handleBadHash(res; body){.dirty.} =
  try:
    body
  except DictError:
    res = newTypeError badHashMsg
    return

proc getitemImpl(self: PyDictObject, other: PyObject): PyObject =
  checkHashableTmpl(other)
  result.handleBadHash:
    result = self.table.getOrDefault(other, nil)
  if not (result.isNil):
    return result
  return keyError other
implDictMagic getitem, [mutable: read]: self.getitemImpl other

implDictMagic setitem, [mutable: write]:
  checkHashableTmpl(arg1)
  result.handleBadHash:
    self.table[arg1] = arg2
  pyNone

proc pop*(self: PyDictObject, other: PyObject, res: var PyObject): bool =
  ## - if `other` not in `self`, `res` is set to KeyError;
  ## - if in, set to value of that key;
  ## - if `DictError`_ raised, `res` is set to TypeError
  res.checkHashableTmpl(other)
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
  checkhashabletmpl(key)
  if args.len == 1:
    return self.getitemimpl key
  checkargnum 2
  let defval = args[1]
  result.handleBadHash:
    return self.table.getOrDefault(key, defVal)

implDictMethod pop, [mutable: write]:
  checkargnumatleast 1
  let key = args[0]
  checkhashabletmpl(key)
  if args.len == 1:
    return self.delitemimpl key
  checkargnum 2
  let defval = args[1]
  if self.pop(key, result):
    return
  # XXX: Python's dict.pop(k, v) discard TypeError, KeyError
  return defval

implDictMethod setdefault, [mutable: write]:
  checkargnumatleast 1
  let key = args[0]
  checkhashabletmpl(key)
  let defVal = if args.len == 1: pyNone
  else:
    checkargnum 2
    args[1]

  result.handleBadHash:
    if key in self:
      return self[key]
    self[key] = defVal
    return defval

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
