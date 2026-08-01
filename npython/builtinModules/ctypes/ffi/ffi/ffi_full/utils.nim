
import ./pyimp
impFfi decl
impCtypes cdata
import ./types
import pkg/libffi
import pkg/py_locale_utf8_encoding/wchar_t as wcharLib
impObjects [
  pyobject,
  noneobject,
  typeobject,
  exceptions,
  stringobject,
  boolobjectImpl,
  dictobject,
  listobject,
  tupleobject,
  typeobject,
  abstract/sequence/list,
]
impObjects numobjects/floatobject
impObjects numobjects/intobject/ops_toint

impFrom Objects, hash, nil
imp Utils, [addr0, destroyPatch, utils]
imp Python, [getargs/tovals, call]

template typeInfo*[T](k: CTypeKind, ffiTypeObj: T): CTypeInfo =
  CTypeInfo(kind: k, ffiType: addr ffiTypeObj)

template genUnOrSigned(signed; sint) {.dirty.} =
  bind typeInfo
  template signed*(T: typedesc): CTypeInfo =
    typeInfo(`ck signed`, 
      when sizeof(T) <= 1: `type sint 8`
      elif sizeof(T) <= 2: `type sint 16`
      elif sizeof(T) <= 4: `type sint 32`
      else: `type sint 64`
    )
genUnOrSigned   signed, sint
genUnOrSigned unsigned, uint

template signedOf*(typeT): CTypeInfo =
  bind typeInfo
  typeInfo(ckSigned, `type_s typeT`)
template unsignedOf*(typeT): CTypeInfo =
  bind typeInfo
  typeInfo(ckUnsigned, `type typeT`)

proc isCFuncType*(typ: PyTypeObject): bool {.raises: [].} =
  var cur = typ
  while not cur.isNil:
    if cur.isType pyCFuncObjectType:
      return true
    cur = cur.base


proc hash(obj: PyTypeObject): Hash{.raises: [].} = hash.rawHash obj
proc ctypeInfo*(tp: PyTypeObject): CTypeInfo {.raises: [].} =

  let tab{.global.} = toTable {
     pyCVoidPObjectType:     typeInfo(ckPointer, type_pointer)
    ,pyCCharPObjectType:     typeInfo(ckCString, type_pointer)
    ,pyCWcharPObjectType:    typeInfo(ckCWString,type_pointer)
    ,pyCBoolObjectType:      typeInfo(ckBool,    type_uint8)
    ,pyCFloatObjectType:     typeInfo(ckFloat,   type_float)
    ,pyCDoubleObjectType:    typeInfo(ckDouble,  type_double)
    ,pyCCharObjectType:      signedOf(int8)
    ,pyCWcharObjectType:     unsigned(wchar_t)
    ,pyCByteObjectType:      signedOf(int8)
    ,pyCUbyteObjectType:     unsignedOf(uint8)
    ,pyCShortObjectType:     signed(cshort)
    ,pyCUshortObjectType:    unsigned(cushort)
    ,pyCIntObjectType:       signed(cint)
    ,pyCUintObjectType:      unsigned(cuint)
    ,pyCLongObjectType:      signed(clong)
    ,pyCUlongObjectType:     unsigned(culong)
    ,pyCLonglongObjectType:  signed(clonglong)
    ,pyCUlonglongObjectType: unsigned(culonglong)
    ,pyCInt8ObjectType:      signedOf(int8)
    ,pyCUint8ObjectType:     unsignedOf(uint8)
    ,pyCInt16ObjectType:     signedOf(int16)
    ,pyCUint16ObjectType:    unsignedOf(uint16)
    ,pyCInt32ObjectType:     signedOf(int32)
    ,pyCUint32ObjectType:    unsignedOf(uint32)
    ,pyCInt64ObjectType:     signedOf(int64)
    ,pyCUint64ObjectType:    unsignedOf(uint64)
    ,pyCSizeTObjectType:     unsigned(csize_t)
    ,pyCSsizeTObjectType:    signed(csize_t)
    ,pyCTimeTObjectType:     signed(int)
  }
  tab.withValue tp, value:
    return value

  if tp.isPointerType:
    return CTypeInfo(
      kind: ckPointer,
      ffiType: addr type_pointer,
      target: tp.pointerTargetType,
    )

  if tp.isCFuncType:
    return CTypeInfo(kind: ckPointer, ffiType: addr type_pointer, target: tp)

  CTypeInfo(kind: ckVoid, ffiType: nil)

proc ctypeInfo*(tp: PyObject, allowVoidInC: bool): CTypeInfo =
  if tp.isNil:
    return signed(cint)
  if tp.isPyNone:
    if allowVoidInC:
      return typeInfo(ckVoid, type_void)
    return CTypeInfo(kind: ckVoid, ffiType: nil)

  if not (tp of PyTypeObject):
    return CTypeInfo(kind: ckVoid, ffiType: nil)
  let typ = PyTypeObject tp
  ctypeInfo(typ)

proc unsupportedCType*(tp: PyObject): PyObject =
  if tp.isNil:
    return newNotImplementedError newPyAscii"ctypes ffi does not support this type"
  newNotImplementedError newPyStr("ctypes ffi does not support " & tp.typeName)

