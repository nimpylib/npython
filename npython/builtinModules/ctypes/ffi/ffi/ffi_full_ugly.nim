
include ./aheader
import pkg/libffi
import pkg/py_locale_utf8_encoding/wchar_t as wcharLib
import ../../[cdata, utils, funcs]
impObjects [
  boolobjectImpl,
  listobject,
  tupleobject,
  abstract/sequence/list,
]
impObjects numobjects/floatobject
impObjects numobjects/intobject/ops_toint

impFrom Objects, hash, nil
imp Utils, [addr0, destroyPatch, utils]
proc hash(obj: PyTypeObject): Hash{.raises: [].} = hash.rawHash obj

type
  CTypeKind = enum
    ckVoid,
    ckBool,
    ckSigned,
    ckUnsigned,
    ckFloat,
    ckDouble,
    ckPointer,
    ckCString,
    ckCWString,
const ckPointers = {ckPointer..ckCWString}

type
  CTypeInfo = object
    kind: CTypeKind
    ffiType: ptr Type

  FFIValue = object
    case kind: CTypeKind
    of ckVoid: discard
    of ckBool:
      b: bool
    of ckSigned:
      s64: int64
    of ckUnsigned:
      u64: uint64
    of ckFloat:
      f32: cfloat
    of ckDouble:
      f64: cdouble
    of ckPointer:
      p: pointer
    of ckCString:
      s: cstring
    of ckCWString:
      ws: ptr wchar_t
    keepalive: PyObject

proc allocCWCharP(self: PyStrObject, res: var ptr wchar_t): PyOverflowErrorObject =
  res = cast[ptr wchar_t](alloc self.len+1)
  var p: int = cast[int](res)
  template setPtrVal(p: int, v: wchar_t) =
    (cast[ptr wchar_t](p))[] = v
  template loop(asciiStr, cvt) {.dirty.} =
    for i in self.str.asciiStr:
      p.setPtrVal cvt i
      p.inc

  template wcharOrOF(r: Rune): wchar_t =
    when sizeof(wchar_t) == sizeof(r): cast[wchar_t](r)
    else:
      static:assert sizeof(wchar_t) == 2
      if r.ord <= high uint16: cast[wchar_t](r)
      else:
        return newOverflowError newPyAscii(
          "str contains char of ord " & $r & " that cannot be fit in wchar_t: "
        )
  if self.isAscii: loop asciiStr, wchar_t
  else: loop unicodeStr, wcharOrOF
  p.setPtrVal wchar_t(0)

defdestroy FFIValue:
  if self.kind == ckCWString: dealloc self.ws

template typeInfo(k: CTypeKind, ffiTypeObj: untyped): CTypeInfo =
  CTypeInfo(kind: k, ffiType: addr ffiTypeObj)


template genUnOrSigned(signed; sint) {.dirty.} =
  template signed(T: typedesc): CTypeInfo =
    typeInfo(`ck signed`, 
      when sizeof(T) <= 1: `type sint 8`
      elif sizeof(T) <= 2: `type sint 16`
      elif sizeof(T) <= 4: `type sint 32`
      else: `type sint 64`
    )
genUnOrSigned   signed, sint
genUnOrSigned unsigned, uint

template signedOf(typeT): CTypeInfo =
  typeInfo(ckSigned, `type_s typeT`)
template unsignedOf(typeT): CTypeInfo =
  typeInfo(ckUnsigned, `type typeT`)

proc ctypeInfo(tp: PyTypeObject): CTypeInfo =

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

  CTypeInfo(kind: ckVoid, ffiType: nil)

proc ctypeInfo(tp: PyObject, allowVoidInC: bool): CTypeInfo =
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


proc inferArgInfo(arg: PyObject): CTypeInfo =
  if arg.ofPySimpleCDataObject:
    let raw = PySimpleCDataObject(arg)
    let size = raw.pyType.ctypeSizeUnsafe()
    case size
    of 1: signedOf int8
    of 2: signedOf int16
    of 4: signedOf int32
    of 8: signedOf int64
    else: unreachable "not impl"  #TODO:ctypes: what about array?
  else:
    let raw = arg
    #XXX: as I tested, following are supported
    if raw.isPyNone:
      return typeInfo(ckPointer, type_pointer)
    if raw.ofPyBytesObject:
      return typeInfo(ckCString, type_pointer)
    if raw.ofPyStrObject:
      return typeInfo(ckCWString, type_pointer)
    if raw.ofPyBoolObject:
      return typeInfo(ckBool, type_uint8)
    # CFunc defaults to use cint as argtype
    return signed(cint)

proc unsupportedCType(tp: PyObject): PyObject =
  if tp.isNil:
    return newNotImplementedError newPyAscii"ctypes ffi does not support this type"
  newNotImplementedError newPyStr("ctypes ffi does not support " & tp.typeName)

proc argtypeItems(self: PyCFuncObject, argsLen: int): PyObject =
  if self.argtypes.isNil or self.argtypes.isPyNone:
    return nil
  result = PySequence_Fast(self.argtypes, "argtypes must be a sequence")
  retIfExc result
  if PySequence_Fast_GET_SIZE(result) != argsLen:
    return newTypeError newPyAscii(
      "this function takes exactly " & $PySequence_Fast_GET_SIZE(result) & " arguments")

proc getArgType(argtypes: PyObject, idx: int): PyObject =
  if argtypes.isNil:
    nil
  else:
    PySequence_Fast_GET_ITEM(argtypes, idx)

proc stripCType(arg: PyObject): PyObject{.inline.} =
  if arg.ofPySimpleCDataObject:
    PySimpleCDataObject(arg).value
  else: arg

proc prepareArg(arg: PyObject, info: CTypeInfo, res: var FFIValue): PyBaseErrorObject =
  res = FFIValue(kind: info.kind)
  case info.kind
  of ckVoid: unreachable
  of ckBool:
    let raw = stripCType(arg)
    retIfExc PyObject_IsTrue(raw, res.b)
  of ckSigned:
    let raw = stripCType(arg)
    retIfExc PyNumber_AsSomeInteger(raw, res.s64)
  of ckUnsigned:
    let raw = stripCType(arg)
    retIfExc PyNumber_AsSomeInteger(raw, res.u64)
  of ckFloat:
    let raw = stripCType(arg)
    var f: float32
    retIfExc PyFloat_AsFloat(raw, f)
    res.f32 = cfloat f
  of ckDouble:
    let raw = stripCType(arg)
    var f: float
    retIfExc PyFloat_AsDouble(raw, f)
    res.f64 = cdouble f
  of ckPointer:
    if arg.isPyNone:
      res.p = nil
    elif arg.ofPyIntObject:
      var address: int
      retIfExc PyNumber_AsSomeInteger(arg, address)
      res.p = cast[pointer](address)
    else:
      return newTypeError newPyAscii"pointer argument expected"
  of ckCString:
    let raw = stripCType(arg)
    if raw.isPyNone:
      res.s = nil
    elif raw.ofPyBytesObject:
      res.keepalive = raw
      res.s = PyBytesObject(raw).asCString
    else:
      return newTypeError newPyAscii"bytes argument expected"
  of ckCWString:
    let raw = stripCType(arg)
    if raw.isPyNone:
      res.ws = nil
    elif raw.ofPyStrObject:
      retIfExc PyStrObject(raw).allocCWCharP res.ws
      res.keepalive = raw
    else:
      return newTypeError newPyAscii"unicode string argument expected"

proc argPtr(value: var FFIValue): pointer =
  case value.kind
  of ckVoid: nil
  of ckBool:
    addr value.b
  of ckSigned:
    addr value.s64
  of ckUnsigned:
    addr value.u64
  of ckFloat:
    addr value.f32
  of ckDouble:
    addr value.f64
  of ckPointer:
    addr value.p
  of ckCString:
    addr value.s
  of ckCWString:
    addr value.ws

proc resultToPy(info: CTypeInfo, resultValue: var FFIValue, restype: PyObject): PyObject{.raises: [].} =
  case info.kind
  of ckVoid: pyNone
  of ckBool:
    newPyBool(resultValue.b)
  of ckSigned:
    newPyInt(resultValue.s64)
  of ckUnsigned:
    newPyInt(resultValue.u64)
  of ckFloat:
    newPyFloat(resultValue.f32)
  of ckDouble:
    newPyFloat(resultValue.f64)
  of ckPointer:
    newPyIntFromPtr(resultValue.p)
  of ckCString:
    newPyBytes(resultValue.s)
  of ckCWString:
    newPyStr(resultValue.ws)

implDynCall:
  let argtypes = argtypeItems(self, args.len)
  if not argtypes.isNil:
    retIfExc argtypes
  let restype = self.restype
  let retInfo = ctypeInfo(restype,
    allowVoidInC = true  # restype can be `void`
  )
  if retInfo.ffiType.isNil:
    return unsupportedCType(restype)

  var
    ffiTypes = newSeq[ptr Type](args.len)
    argValues = newSeq[FFIValue](args.len)
    argPointers = newSeq[pointer](args.len)
  for i, arg in args:
    let argtype = getArgType(argtypes, i)
    let argInfo =
      if argtype.isNil: inferArgInfo(arg)
      else: ctypeInfo(argtype, allowVoidInC = false)
    if argInfo.ffiType.isNil:
      return unsupportedCType(argtype)
    ffiTypes[i] = argInfo.ffiType
    retIfExc prepareArg(arg.stripCType, argInfo, argValues[i])
    argPointers[i] = argPtr(argValues[i])

  var cif: TCif
  if prep_cif(cif, DEFAULT_ABI, cuint args.len, retInfo.ffiType,
      ffiTypes.addr0) != OK:
    return newRuntimeError newPyAscii"ffi_prep_cif failed"

  var resultValue = FFIValue(kind: retInfo.kind)
  call(cif, cast[proc(){.cdecl.}](self.handle), argPtr(resultValue),
      argPointers.addr0)
  resultToPy(retInfo, resultValue, restype)

