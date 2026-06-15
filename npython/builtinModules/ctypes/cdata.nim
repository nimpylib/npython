
import std/macros
import pkg/py_locale_utf8_encoding/wchar_t
import ../private/[utils]
import ./common
import ./cdata/ints

impObjects [
  pyobject,
  boolobjectImpl,
  stringobject,
  numobjects,
  byteobjects,
  dictobject,
  exceptions,
  noneobject,
  typeobject,
  pyobject_apis/attrsGeneric,
]
impObjects pyobject_apis/strings
imp Include, internal/pycore_global_strings
imp Python, getargs/tovals

declarePyType SimpleCData(dict, typeName("_SimpleCData")):
  discard

template notImpl = doAssert false, "notImpl"
method value*(self: `PySimpleCDataObject`): PyObject{.base, raises: [].} = notImpl
method setValue*(self: `PySimpleCDataObject`, value: PyObject): PyBaseErrorObject{.base, raises: [].} = notImpl

var ctypeClasses{.compileTime.}: seq[
  tuple[pyname, typeId: string]
]
macro forEachCTypeClass(action) =
  result = newStmtList quote do:
    `action`("_SimpleCData", pySimpleCDataObjectType)
    # alias
    `action`("c_voidp", pyCVoidPObjectType)
  for (name, id) in ctypeClasses:
    result.add newCall(action,
                       newStrLitNode name, ident id)

template registerCTypeClasses*(dict: PyDictObject) =
  bind forEachCTypeClass
  template addCTypeClass(pyName: static[string], pyTypeObj: PyTypeObject) =
    dict[newPyAscii pyName] = pyTypeObj
  forEachCTypeClass(addCTypeClass)
macro decl(id, T; name: static[string]) = quote do:
  declarePyType `id`(base(SimpleCData), typeName(`name`)):
    pri_value{.private.}: `T`

template cannotAs(T) =
  return newTypeError newPyAscii '\'' & self.typeName & "' object cannot be interpreted as " & $T
template declarePyCType(id, T, PyT; elseDo) {.dirty.} =
  bind decl
  const `id name` = astToStr(id)
  decl id, T, `id name`
  static:
    ctypeClasses.add (`id name`, "py" & astToStr(id) & "ObjectType")
  proc `newPy id`*(): `Py id Object`{.raises: [].} =
    result = `newPy id Simple`()
  proc `newPy id`*(value: `T`): `Py id Object`{.raises: [].} =
    result = `newPy id`()
    result.pri_value = value
  #proc `newPy id`*(value: `Py PyT Object`): `Py id Object`{.raises: [].} =
  method value*(self: `Py id Object`): PyObject{.raises: [].} = `newPy PyT` self.pri_value
  proc setValue*(self: `Py id Object`, value: `Py PyT Object`): PyBaseErrorObject =
    retIfExc toval(value, self.pri_value)
  method setValue*(self: `Py id Object`, value: PyObject): PyBaseErrorObject{.raises: [].} =
    if value.`ofPy PyT Object`:
      return self.setValue `Py PyT Object` value
    elseDo
  proc `value=`*(self: `Py id Object`, value: T) = self.pri_value = value
  proc `newPy id`*(value: PyObject): PyObject{.raises: [].} =
    let res = `newPy id`()
    retIfExc res.setValue value
    result = res
  `impl id Magic` New(tp: PyObject, value = PyObject nil):
    if value.isNil: `newPy id`()
    else: `newPy id`(value)
template declarePyCType(id, T, PyT) {.dirty.} =
  bind cannotAs
  declarePyCType id, T, PyT, cannotAs T

declarePyCType c_void_p, int, int

# c_wchar
template typerr_c_wcharAux(suf = "") {.dirty.} =
  return newTypeError newPyAscii "a unicode character expected, not " & suf
template typerr_c_wchar_not(obj: PyStrObject) {.dirty.} =
  typerr_c_wcharAux "a string of length " & $obj.len
template typerr_c_wchar_not(obj: PyObject) {.dirty.} =
  typerr_c_wcharAux "instance of " & obj.typeName
proc toval(obj: PyStrObject, c: var wchar_t): PyBaseErrorObject =
  if obj.len == 1:
    let rune = obj[0]
    when sizeof(c) < sizeof(typeof(rune)):
      if rune > high wchar_t:
        return newOverflowError newPyAscii "str's character is a UCS4 " &
          "which cannot fit into wchar_t (whose size is 2)"
    c = cast[wchar_t](rune)
    return
  typerr_c_wchar_not obj
proc newPyStr(c: wchar_t): PyObject =
  newPyStr @[Rune c]
declarePyCType c_wchar, wchar_t, str:
  typerr_c_wchar_not value

# c_char
template typerr_c_charAux(suf = "") {.dirty.} =
  return newTypeError newPyAscii "one character bytes, bytearray, or an integer in range(256) expected, not " & suf
template typerr_c_char_not(obj: PyBytesObject|PyByteArrayObject) {.dirty.} =
  typerr_c_charAux obj.typeName & " of length " & $obj.len
template typerr_c_char_not(obj: PyObject) {.dirty.} =
  typerr_c_charAux obj.typeName
proc toval(obj: PyBytesObject, c: var char): PyBaseErrorObject =
  if obj.len == 1:
    c = obj[0]
    return
  typerr_c_char_not obj
declarePyCType c_char, char, bytes:
  if value.ofPyIntObject:
    let ivalue = PyIntObject(value)
    var ovf: IntSign
    let ui = ivalue.toSomeUnsignedInt[:uint8](ovf)
    if ovf == IntSign.Zero:
      self.pri_value = cast[char](ui)
      return
  if value.ofPyByteArrayObject:
    let ba = PyByteArrayObject(value)
    if ba.len == 1:
      self.pri_value = ba[0]
    typerr_c_char_not ba
  typerr_c_char_not value

# c_char_p
template toval(x: PyBytesObject, res: var cstring): PyBaseErrorObject =
  res = cast[cstring](x.items[0].addr)
  PyBaseErrorObject nil

proc newPyBytes(s: cstring): PyObject =
  if s.isNil: pyNone
  else: newPyBytes s.toOpenArray(0, s.high)

declarePyCType c_char_p, cstring, bytes:
  if value.isPyNone:
    self.pri_value = cstring nil
    return
  if value.ofPyIntObject:
    var i: int
    retIfExc toval(value, i)
    self.pri_value = cast[cstring](i)
    return
  return newTypeError newPyStr "bytes or integer address expected instead of " & value.typeName & " instance" 

declarePyCType c_bool, bool, bool:
  return PyObject_IsTrue(value, self.pri_value)

template decl_int(pyId, nimId) {.dirty.} =
  declarePyCType pyId, nimId, int

gen_ints_decl decl_int

proc toval[T: SomeInteger](x: PyIntObject, res: var T): PyBaseErrorObject =
  var ovf: IntSign
  res = (when T is SomeSignedInt: toSomeSignedInt else: toSomeUnsignedInt)[T](x, ovf)
  if ovf != IntSign.Zero: return PyInt_OverflowCType $T

decl_all_ints


declarePyCType c_double, c_double, float
declarePyCType c_float, c_float, float

genProperty SimpleCData, "value", value, self.value:
  retIfExc self.setValue other
  pyNone

implSimpleCDataMagic repr:
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
    retIfExc self.setValue arg2
    return pyNone
  PyObject_GenericSetAttr(self, arg1, arg2)

