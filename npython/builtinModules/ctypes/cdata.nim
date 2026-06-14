
import std/macros
import ../private/[utils]
import ./common

impObjects [
  pyobject,
  stringobject,
  byteobjects,
  dictobject,
  exceptions,
  noneobject,
  typeobject,
  pyobject_apis/attrsGeneric,
]
impObjects pyobject_apis/strings
impObjects numobjects/intobject
imp Include, internal/pycore_global_strings
imp Python, getargs/tovals


declarePyType SimpleCData(dict, typeName("_SimpleCData")):
  value: PyObject

var ctypeClasses{.compileTime.}: seq[
  tuple[pyname, typeId: string]
]
macro decl(id; name: static[string]) = quote do:
  declarePyType `id`(base(SimpleCData), typeName(`name`)):
    discard
template declarePyCType(id) {.dirty.} =
  const `id name` = astToStr(id)
  decl id, `id name`
  static:
    ctypeClasses.add (`id name`, "py" & astToStr(id) & "ObjectType")
  proc `newPy id`*(value: PyObject): `Py id Object`{.raises: [].} =
    result = `newPy id Simple`()
    result.value = value

declarePyCType c_char_p
declarePyCType c_int

macro forEachCTypeClass(action) =
  result = newStmtList quote do:
    `action`("_SimpleCData", pySimpleCDataObjectType)
  for (name, id) in ctypeClasses:
    result.add newCall(action,
                       newStrLitNode name, ident id)

template registerCTypeClasses*(dict: PyDictObject) =
  bind forEachCTypeClass
  template addCTypeClass(pyName: static[string], pyTypeObj: PyTypeObject) =
    dict[newPyAscii pyName] = pyTypeObj
  forEachCTypeClass(addCTypeClass)

genProperty SimpleCData, "value", value, self.value:
  self.value = other
  pyNone

implSimpleCDataMagic repr:
  assert self.value.isNil.not
  let value = self.value
  let valueRepr = PyObject_ReprNonNil(value)
  retIfExc valueRepr
  newPyStr(self.typeName & "(" & $PyStrObject(valueRepr).str & ")")

implSimpleCDataMagic getattr:
  let name = other.attrName
  if name.eqAscii"value":
    return self.value
  PyObject_GenericGetAttr(self, other)

implSimpleCDataMagic setattr:
  let name = arg1.attrName
  if name.eqAscii"value":
    self.value = arg2
    return pyNone
  PyObject_GenericSetAttr(self, arg1, arg2)

implCIntMagic New(tp: PyObject, value = PyObject pyIntZero):
  newPyCInt(value)

implCCharPMagic New(tp: PyObject, value = PyObject pyNone):
  newPyCCharP(value)

