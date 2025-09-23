
#import std/strformat as std_fmt
import ./pyobject_apis/strings
import ./[
  pyobject,
  exceptions,
  stringobjectImpl,
  dictobjectImpl,
  boolobject,
  noneobject,
  #typeobject,
  notimplementedobject,
]
import ./typeobject/apis/subtype

import ../Python/getargs/[
  vargs, kwargs,
]

declarePyType Namespace(dict, reprLock): discard

using self: PyNamespaceObject
method `$`*(self): string{.pyCFuncPragma.}= self.typeName & '(' & "..." & ')'

proc getDict(self): PyDictObject = PyDictObject self.dict

implNamespaceMagic repr, [reprLockWithMsgExpr(self.typeName&"(...)")]:
  let name = #if self.pyType.isType pyNamespaceObjectType: "namespace" else:
    self.typeName
  assert not self.dict.isNil
  var sequ = newSeq[PyStrObject]()
  var ks: PyStrObject
  for key, value in self.getDict.pairs():
    if key.ofPyStrObject and (ks=PyStrObject key; ks).len > 0:
      let valS = PyObject_ReprNonNil(value)
      retIfExc valS
      let s = ks & newPyAscii"=" & PyStrObject(valS)
      #newPyStr&"{key:U}={value:R}" \
      #XXX:NIM-BUG: writing as above produces bad JS: `nimCopy(null, ,`
      sequ.add s
  let maye_pairsrepr = newPyAscii", ".join sequ
  retIfExc maye_pairsrepr
  let pairsrepr = PyStrObject maye_pairsrepr
  result = newPyStr(name) & newPyAscii"(" & pairsrepr & newPyAscii")"

proc newPyNamespace*(): PyNamespaceObject = newPyNamespaceSimple()
proc updateDict(np: PyNamespaceObject, o: PyDictObject) =
  np.getDict.updateImpl o

proc newPyNamespace*(kwds: PyDictObject): PyNamespaceObject =
  ## `_PyNamespace_New`
  result = newPyNamespace()
  result.updateDict kwds

proc namespace_init(op: PyObject, args: openarray[PyObject], kwds: PyObject): PyObject =
  result = pyNone
  let ns = PyNamespaceObject op
  var arg: PyObject
  PyArg_UnpackTuple(ns.typeName, args, 0, 1, arg)
  if not arg.isNil:
    var dictObj: PyObject
    if arg.ofPyDictObject():
      dictObj = arg
    else:
      dictObj = pyDictObjectType.magicMethods.New([arg], nil)
      retIfExc dictObj
    let dict = PyDictObject dictObj
    retIfExc PyArg_ValidateKeywordArguments(dict)
    ns.updateDict dict
  if kwds.isNil: return

  retIfExc PyArg_ValidateKeywordArguments(kwds)
  ns.updateDict PyDictObject kwds

implNamespaceMagic init: namespace_init self, args, kwargs

implNamespaceMagic eq, [noSelfCast]:
  if PyObject_TypeCheck(selfNoCast, pyNamespaceObjectType) and
     PyObject_TypeCheck(other, pyNamespaceObjectType):
    return newPyBool selfNoCast.PyNamespaceObject.getDict ==
          other.PyNamespaceObject.getDict
  pyNotImplemented

proc replace*(self: PyNamespaceObject, kwargs: PyDictObject): PyObject =
  result = self.pyType.magicMethods.New([PyObject self], nil)
  retIfExc result
  let res = PyNamespaceObject result
  res.getDict.updateImpl self.getDict
  return res

implNamespaceMethod "__replace__"(**kw): self.replace(kw)




