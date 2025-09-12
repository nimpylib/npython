import strformat


import tables
import macros

import pyobject 
# import listobject (do not import, or it'll cause recursive import)
import ./[
  exceptions, stringobject, boolobject, noneobject,
  ]
import ./numobjects/intobject_decl
import ../Utils/[utils, optres]
export GetItemRes
import ./[iterobject, tupleobject]

import ./hash
import ./dictobject/[ops, helpers]
export ops
methodMacroTmpl(Dict)

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

implDictMagic len, [mutable: read]: newPyInt self.len

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

template handleBadHash(res; body){.dirty.} =
  template setRes(e) = res = e
  handleHashExc setRes:
    body

implDictMagic getitem, [mutable: read]: self.getitem other

template setItemImpl(self, arg1, arg2) =
  result.handleBadHash:
    self.table[arg1] = arg2
proc setItem*(dict: PyDictObject, key, value: PyObject): PyBaseErrorObject =
  dict.setItemImpl(key, value)

implDictMagic setitem, [mutable: write]:
  self.setItemImpl(arg1, arg2)
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

proc pop*(self: PyDictObject, other: PyStrObject, res: var PyObject): bool =
  ## no exception may be raised
  DictError!self.table.pop(other, res)

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
