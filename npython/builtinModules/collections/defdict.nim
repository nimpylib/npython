

import ../private/utils
impObjects [
  pyobject,
  exceptions,
  dictobject,
  stringobjectImpl,
  tupleobjectImpl,
  descrobject,
  noneobject,
]
impObjects dictobject/helpers
impObjects pyobject_apis/strings
imp Python, getargs/tovals
imp Python, call

declarePyType defaultdict(base(dict)):
  default_factory{.member,nil2none.}: PyObject
  dfReprLock: bool

proc newPyDefaultDict*(default_factory: PyObject): PyDefaultDictObject =
  result = newPydefaultdictSimple()
  result.default_factory = default_factory

impldefaultdictMethod "__missing__"(key):
  let df = self.default_factory
  if df.isNil or df.isPyNone:
    return keyError key
  let value = call(df)
  retIfExc value
  self.setdefault value

impldefaultdictMagic init(default_factory=PyObject pyNone, *args, **kwargs):
  self.default_factory = default_factory
  pyDictObjectType.magicMethods.init(self, args, kwargs)

using self: PyDefaultDictObject
proc getDefaultFactory(self): PyObject =
 if self.default_factory.isNil: pyNone else: self.default_factory

proc new_defdict(op: PyDefaultDictObject, arg: PyObject): PyObject =
  fastCall(op.pyType, [op.getDefaultFactory, arg])
impldefaultdictMethod copy(): new_defdict(self, self)
impldefaultdictMethod "__copy__"(): new_defdict(self, self)

proc `|`*(self; other: PyDictObject): PyObject =
  result = new_defdict(self, self)
  retIfExc result
  PyDictObject(result).update other

impldefaultdictMagic Or:
  let (left, right) = (self, other)
  block:
    let (self, other) =
      if left.ofPydefaultdictObject: (left, right)
      else:
        assert right.ofPydefaultdictObject
        (PyDefaultDictObject right, left)
    if not other.ofPyDictObject: return pyNotImplemented

    let ne = new_defdict(self, left)
    retIfExc ne
    PyDictObject(ne).update(PyDictObject right)

template reprImpl(self): tuple[baserepr, defrepr: PyStrObject] =
  let basereprObj = pyDictObjectType.magicMethods.repr(self)
  retIfExc basereprObj
  let baserepr = PyStrObject basereprObj
  var defrepr: PyStrObject
  try:
    if self.dfReprLock:
      defrepr = newPyAscii("...")
    else:
      let defreprObj = PyObject_ReprNonNil self.getDefaultFactory
      retIfExc defreprObj
      defrepr = PyStrObject(defreprObj)

      self.dfReprLock = true

  finally:
    self.dfReprLock = false
  (baserepr, defrepr)

impldefaultdictMagic repr:
  let (baserepr, defrepr) = self.reprImpl
  newPyStr(self.typeName & '(' & defrepr.asUTF8 & ", " & baserepr.asUTF8 & ')')

