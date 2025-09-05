

import ./pyobject
import ../Python/call
import ./[stringobject, iterobject, numobjects]
import ./noneobject
import ./exceptions
import ./dictobject
export dictobject
from ../Utils/utils import DictError, `!!`

# redeclare this for these are "private" macros

methodMacroTmpl(Dict)




proc updateImpl*(self: PyDictObject, E: PyObject): PyObject{.raises: [].} =
  if E.ofPyDictObject:
    DictError!!self.update(PyDictObject E)
    return pyNone
  let
    keysFunc = E.callMagic(getattr, newPyAscii"keys")  # getattr(E, "keys")
    getitem = E.getMagic(getitem)
  if not keysFunc.isThrownException and not getitem.isNil:
    let ret = fastCall(keysFunc, [])
    if ret.isThrownException: return ret
    handleHashExc:
      pyForIn i, ret:
        self[i] = getitem(E, i)
  else:
    var idx = 0
    pyForIn ele, E:
      let getter = ele.getMagic(getitem)
      if getter.isNil:
        return newTypeError newPyAscii(
          "cannot convert dictionary update sequence element #" &
          $idx & " to a sequence")
      # only use getitem
      let
        k = getter(ele, pyIntZero)
        v = getter(ele, pyIntOne)
      handleHashExc: self[k] = v
      idx.inc
  pyNone

implDictMagic iOr(E: PyObject), [mutable: write]: self.updateImpl E

# XXX: how to impl using std/table?
# implDictMethod popitem(), [mutable: write]:

implDictMethod update(E: PyObject), [mutable: write]:
  # XXX: `**kw` not supported in syntax
  self.updateImpl E

implDictMagic init:
  let argsLen = args.len
  case argsLen
  of 0: pyNone
  of 1:
    let ret = self.updateImpl(args[argsLen-1])
    if ret.isThrownException: return ret
    pyNone
  else:
    errArgNum argsLen, 1
