
import std/strformat
import ../Include/cpython/pyatomic
import ../Objects/[
  pyobjectBase, exceptions,
  numobjects, boolobject, stringobjectImpl, noneobject,
]
import ./[
  warnings, errors,
]

import ../Include/descrobject

const Js = defined(js)
when Js:
  # As of Nim 2.3.1, ref object or object is simply
  #  JS object with some metadata as attributes
  type JsSimpObj = (ref object)|object
  proc getattrAs[T](o: JsSimpObj, s: cstring): T{.importjs: "#[#]".}
  proc getattrAs[T](o: JsSimpObj, s: string): T = getattrAs[T](o, cstring s)

  proc setattr[T](o: JsSimpObj, s: cstring, v: T){.importjs: "#[#] = #;".}
  proc setattr[T](o: JsSimpObj, s: string, v: T) = setattr[T](o, cstring s, v)

  type Addr = PyObject
  template loadAt[T](p: Addr): T =
    mixin fieldName
    getattrAs[T](p, fieldName)

  template storeAt[T](p: Addr; v: T) =
    mixin fieldName
    setattr p, fieldName, v

else:
  type Addr = pointer|int
  proc loadAt[T](p: Addr): T{.cdecl,inline.} =
    Py_atomic_load_relaxed(cast[ptr T](p))

  template storeAt[T](p: ptr T, v: T) = Py_atomic_store_relaxed(p, v)
  template storeAt[T](p: Addr, v: T) = storeAt cast[ptr T](p), v

template genStoreAtP(U, body){.dirty.} =
  template `store U At`(p: Addr, v: PyObject) = body

genStoreAtP PyObject:
  when Js:
    storeAt(p, v)
  else:
    storeAt(p, cast[pointer](v))
    #cast[ptr PyObject](p)[] = v

template roErr =
  return newAttributeError newPyAscii"readonly attribute"

genStoreAtP cstring:
  ## assuming static, readonly
  roErr
genStoreAtP char:
  var
    s: string
    size: int
  let exc = PyUnicode_AsUTF8AndSize(v, s, size)
  if exc.isNil:
    if size != 1:
      return PyErr_BadArgument()
    storeAt(p, s[0])
  else:
    return exc

template sysErr(s: PyStrObject) =
  return newSystemError s

proc PyMember_GetOne*(obj_addr: PyObject, l: PyMemberDef): PyObject =
  l.noRelOff "PyMember_GetOne"
  when Js:
    let a = obj_addr
    let fieldName = l.name
  else:
    let a = cast[int](obj_addr) + l.offset
    template As(T: typedesc[cstring], init) =
      let p = loadAt[ptr char](a)
      result = if p.isNil: pyNone else: init cast[cstring](p)
    template As(T: typedesc[char], init) = result = init loadAt[char](a)
    template As(T: typedesc[PyObject], init) = result = init cast[PyObject](loadAt[pointer](a))
  template As(T; init) = result = init loadAt[T](a)
  template AsInt(T) = result = newPyInt loadAt[T](a)
  template member_get_object(x: PyObject): PyObject{.dirty.} =
    if x.isNil:
      let obj = obj_addr
      newAttributeError newPyStr fmt"'{obj.typeName}' object has no attribute '{l.name}'"
    else: x
  case l.`type`
  of akBool: As bool, newPyBool

  of akInt:   AsInt int
  of akInt8:  AsInt int8
  of akInt16: AsInt int16
  of akInt32: AsInt int32
  of akInt64: AsInt int64
  of akUInt:  AsInt uint
  of akUInt8: AsInt uint8
  of akUInt16:AsInt uint16
  of akUInt32:AsInt uint32
  of akUInt64:AsInt uint64

  of akFloat32: As float32, newPyFloat
  of akFloat64: As float64, newPyFloat

  #of akString: As string, newPyStr
  of akCString: As cstring, newPyStr
  of akChar: As char, newPyStr
  of akPyObject: As PyObject, member_get_object
  of akNone: result = pyNone  # `_Py_T_NONE` Deprecated. Value is always None.
  else: sysErr newPyAscii"bad memberdescr type"

template WARN(s) =
  retIfExc warnEx(pyRuntimeWarningObjectType, s, 1)

proc PyMember_SetOne*(obj_addr: PyObject, l: PyMemberDef, v: PyObject): PyBaseErrorObject =
  l.noRelOff "PyMember_SetOne"
  if l.flags.readonly:
    roErr
  when Js:
    let a = obj_addr
    let fieldName = l.name
  else:
    let a = cast[int](obj_addr) + l.offset
  if v.isNil:
    if l.`type` == akPyObject:
      if loadAt[pointer](a).isNil:
        return newAttributeError newPyStr l.name
  template As(T; toNim) =
    var nv: T
    when compiles(PyBaseErrorObject(v.toNim nv)):
      let exc = v.toNim nv
      if not exc.isNil:
        return exc
    else:
      nv = v.toNim
    storeAt[T] a, nv
  template asIntObj(v): PyIntObject =
    let intObj = PyNumber_Index(v)
    if intObj.isThrownException:
      return PyBaseErrorObject intObj
    PyIntObject intObj
  template warnTrunc(T) =
      WARN("Truncation of value to " & $T)
  template AsInt(T: typedesc[SomeSignedInt]) =
    var res: int
    let exc = v.PyNumber_AsSsize_t res
    if not exc.isNil:
      return exc
    if res.BiggestInt not_in T.low.BiggestInt .. T.high.BiggestInt:
      warnTrunc T
    storeAt[T] a, cast[T](res)

  template AsInt(T: typedesc[SomeUnsignedInt]) =
    var res: uint
    let intObj = v.asIntObj
    if intObj.negative:
      WARN("Writing negative value into unsigned field")
    else:
      if not intObj.absToUInt(res):
        warnTrunc T
    storeAt[T] a, cast[T](res)


  case l.`type`
  of akBool:
    if not v.ofPyBoolObject:
      return newTypeError newPyAscii"attribute value type must be bool"
    storeAt[bool](a, PyBoolObject(v).isPyTrue)
  of akInt:   AsInt int
  of akInt8:  AsInt int8
  of akInt16: AsInt int16
  of akInt32: AsInt int32
  of akInt64: AsInt int64
  of akUInt:  AsInt uint
  of akUInt8: AsInt uint8
  of akUInt16:AsInt uint16
  of akUInt32:AsInt uint32
  of akUInt64:AsInt uint64

  of akFloat32: As float32, PyFloat_AsFloat
  of akFloat64: As float64, PyFloat_AsDouble

  #of akString: As string,
  of akCString: storeCStringAt(a, v)
  of akChar: storeCharAt(a, v)
  of akPyObject: storePyObjectAt(a, v)
  #of akNone: # CPython doesn't allow setting None  

  else: sysErr newPyStr("bad memberdescr type for " & l.name)

