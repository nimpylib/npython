


import ../Python/call
import ./[
  pyobject,
  exceptions, noneobject,
  stringobject, iterobject,
  setobject,
  ]
import ./abstract/[iter, dunder,]
import ./abstract/sequence/list
import ./dictobject
export dictobject
from ../Utils/utils import DictError, `!!`
import ../Python/getargs/vargs
import ../Include/cpython/critical_section

# redeclare this for these are "private" macros

methodMacroTmpl(Dict)




proc updateImpl*(self: PyDictObject, E: PyDictObject){.raises: [].} =
  DictError!!self.update(E)
proc updateImpl*(self: PyDictObject, E: PyObject): PyObject{.raises: [].} =
  if E.ofPyDictObject:
    self.updateImpl(PyDictObject E)
    return pyNone
  let
    keysFunc = E.callMagic(getattr, newPyAscii"keys")  # getattr(E, "keys")
    getitem = E.getMagic(getitem)
  if not keysFunc.isThrownException and not getitem.isNil:
    let ret = fastCall(keysFunc, [])
    retIfExc ret
    handleHashExc:
      pyForIn i, ret:
        let e = getitem(E, i)
        retIfExc e
        self[i] = e
  else:
    var idx = 0
    pyForIn ele, E:
      # Convert item to sequence, and verify length 2.
      let fast = PySequence_Fast(ele, "object is not iterable")
      if fast.isThrownException:
        return newTypeError newPyAscii(
          "cannot convert dictionary update sequence element #" &
          $idx & " to a sequence")
      let n = PySequence_Fast_GET_SIZE(fast)
      if n != 2:
        return newValueError newPyAscii(
          "dictionary update sequence element #" & $idx &
          " has length " & $n & "; 2 is required")

      # only use getitem
      let
        k = PySequence_Fast_GET_ITEM(ele, 0)
        v = PySequence_Fast_GET_ITEM(ele, 1)
      handleHashExc: self[k] = v
      idx.inc
  pyNone

proc updateImpl*(self: PyDictObject, arg: PyObject, kw: PyDictObject): PyObject{.raises: [].} =
  let ret = self.updateImpl(arg)
  retIfExc ret
  assert ret.isPyNone
  result = pyNone
  if kw.isNil: return
  self.updateImpl(kw)

implDictMagic iOr(E: PyObject), [mutable: write]: self.updateImpl E

# XXX: how to impl using std/table?
# implDictMethod popitem(), [mutable: write]:

implDictMethod update, [mutable: write]:
  let argsLen = args.len
  result = case argsLen
  of 0:
    if not kwargs.isNil:
      self.updateImpl(PyDictObject kwargs)
    pyNone
  of 1:
    self.updateImpl(args[argsLen-1], PyDictObject kwargs)
  else:
    errArgNum argsLen, 1
  assert not result.isNil

implDictMagic init: self.updatePyDictObjectMethod(args, kwargs)


proc fromkeys(mp: PyDictObject, iterable: PyDictObject|PySetObject|PyFrozenSetObject, value: PyObject): PyDictObject =
  for k in iterable:
    ## iterable is already a dict, so its keys must be hashable
    DictError!!(mp[k] = value)
  mp

proc PyDict_FromKeys*(cls: PyObject, iterable, value: PyObject): PyObject =
  ## `_PyDict_FromKeys`
  ## Internal version of dict.from_keys().  It is subclass-friendly
  let d = call(cls)
  retIfExc d
  if d.ofExactPyDictObject:
    let mp = PyDictObject d
    template retFor(T) =
      let it = T iterable
      criticalWrite mp: criticalRead it:
        result = mp.fromkeys(it, value)
      return
    if iterable.ofExactPyDictObject:
      retFor PyDictObject
    elif iterable.ofExactPySetObject:
      retFor PySetObject
    elif iterable.ofExactPyFrozenSetObject:
      let it = PyFrozenSetObject iterable
      criticalWrite mp: # `criticalRead it:` # frozenset has no lock
        result = mp.fromkeys(it, value)
      return
  let it = PyObject_GetIter(iterable)
  retIfExc it
  if d.ofExactPyDictObject:
    let mp = PyDictObject d
    criticalWrite mp:
      pyForIn key, it:
        retIfExc mp.setItem(key, value)
  else:
    pyForIn key, it:
      retIfExc PyObject_SetItem(d, key, value)
  d

implDictMethod fromkeys(*a), [classmethod]:
  var
    iterable: PyObject
    value = pyNone
  PyArg_UnpackTuple("fromkeys", a, 1, 2, iterable, value)
  PyDict_FromKeys(selfNoCast, iterable, value)
