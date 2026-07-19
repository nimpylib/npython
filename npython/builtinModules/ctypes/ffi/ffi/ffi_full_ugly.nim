
when defined(nimPrviewSlimSystem):
  import std/assertions
include ./aheader
import pkg/libffi
import pkg/py_locale_utf8_encoding/wchar_t as wcharLib
import ../../cdata
impObjects [
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

type
  CTypeInfo = object
    kind: CTypeKind
    ffiType: ptr Type
    target: PyTypeObject

  FFIValue = object
    kind: CTypeKind
    p: pointer
    pIsAlloced: bool
    p2pIsAlloced: bool
    keepalive: PyObject

proc isCFuncType*(typ: PyTypeObject): bool {.raises: [].} =
  var cur = typ
  while not cur.isNil:
    if cur.isType pyCFuncObjectType:
      return true
    cur = cur.base


defdestroy FFIValue:
  if self.p2pIsAlloced:
    dealloc (cast[ptr pointer](self.p))[]
  if self.pIsAlloced: dealloc self.p

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

  if tp.isPointerType:
    return CTypeInfo(
      kind: ckPointer,
      ffiType: addr type_pointer,
      target: tp.pointerTargetType,
    )

  if tp.isCFuncType:
    return CTypeInfo(kind: ckPointer, ffiType: addr type_pointer, target: tp)

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


proc ctypeSizeUnsafe(typ: PyTypeObject): int {.raises: [].} =
  let size = PyDictObject(typ.dict).getOptionalItem(newPyAscii"_npy_ctype_size_")
  assert size.ofPyIntObject
  PyIntObject(size).toSomeSignedIntUnsafe[:int]

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


proc prepareArg(arg: PyObject, info: CTypeInfo, res: var FFIValue): PyBaseErrorObject =
  res = FFIValue(kind: info.kind)
  template prepForT[T](res: var FFIValue; _: typedesc[T]): ptr T =
    res.pIsAlloced = true
    res.p = alloc sizeof T
    cast[ptr T](res.p)
  template initFrom[T](res: var FFIValue; x: T) =
    res.prepForT(T)[] = x
  template ctypeOr(T; handlePyObj: untyped =
      retIfExc toval(arg, cast[var T](res.prepForT(T)))
    ) =
    if arg.ofPySimpleCDataObject:
      let raw = PySimpleCDataObject(arg)
      #TODO:ctypes: check type/size
      res.p = raw.addressof
    else:
      handlePyObj
  case info.kind
  of ckVoid: unreachable
  of ckBool:    ctypeOr bool
  of ckSigned:  ctypeOr int64
  of ckUnsigned:ctypeOr uint64
  of ckFloat:   ctypeOr float32
  of ckDouble:  ctypeOr float
  of ckPointer:
    if arg.isPyNone:
      res.initFrom pointer(nil)
    elif arg.ofPyCFuncObject:
      let cfunc = PyCFuncObject(arg)
      if not info.target.isNil and not cfunc.pyType.isType(info.target):
        return newTypeError newPyStr("expected " & info.target.name &
          " instance instead of " & arg.typeName)
      res.keepalive = arg
      res.initFrom cfunc.handle
    elif arg.ofPyPointerObject:
      res.keepalive = arg
      res.initFrom PyPointerObject(arg).c_value
    elif not info.target.isNil and arg.ofPyCDataObject:
      let cdata = PyCDataObject(arg)
      if not cdata.pyType.isType info.target:
        return newTypeError newPyStr("expected " & info.target.name &
          " instance instead of " & arg.typeName)
      res.keepalive = arg
      res.initFrom cdata.addressof
    elif arg.ofPyIntObject:
      var address: int
      retIfExc PyNumber_AsSomeInteger(arg, address)
      res.initFrom cast[pointer](address)
    else:
      return newTypeError newPyAscii"pointer argument expected"
  of ckCString:
    ctypeOr cstring:
      if arg.isPyNone:
        res.initFrom cstring(nil)
      elif arg.ofPyBytesObject:
        res.keepalive = arg
        res.initFrom PyBytesObject(arg).asCString  # char view, not copy
      else:
        return newTypeError newPyAscii"bytes argument expected"
  of ckCWString:
    ctypeOr (ptr wchar_t):
      if arg.isPyNone:
        res.initFrom (ptr wchar_t)(nil)
      elif arg.ofPyStrObject:
        res.initFrom PyStrObject(arg).toAllocedWideCString()
        res.p2pIsAlloced = true
        res.keepalive = arg
      else:
        return newTypeError newPyAscii"unicode string argument expected"

template argPtr(value: FFIValue): pointer = value.p

proc resultToPy(info: CTypeInfo, resultValue: FFIValue, restype: PyObject): PyObject{.raises: [].} =
  template asT(T): untyped =
    cast[ptr T](resultValue.p)[]
  template signedValue: int64 =
    case info.ffiType.size
    of 1: int64(asT(int8))
    of 2: int64(asT(int16))
    of 4: int64(asT(int32))
    else: int64(asT(int64))
  template unsignedValue: uint64 =
    case info.ffiType.size
    of 1: uint64(asT(uint8))
    of 2: uint64(asT(uint16))
    of 4: uint64(asT(uint32))
    else: uint64(asT(uint64))
  case info.kind
  of ckVoid: pyNone
  of ckBool:    newPyBool(asT bool)
  of ckSigned:   newPyInt(signedValue)
  of ckUnsigned: newPyInt(unsignedValue)
  of ckFloat:  newPyFloat(asT float32)
  of ckDouble: newPyFloat(asT float64)
  of ckPointer:
    let p = asT pointer
    if not restype.isNil and restype.ofPyTypeObject and PyTypeObject(restype).isPointerType:
      newPyPointerFromAddress(PyTypeObject(restype), p)
    else:
      newPyIntFromPtr(p)
  of ckCString:
    newPyBytes(asT cstring)
  of ckCWString:
    newPyStr(asT (ptr wchar_t))

proc callbackSignature(typ: PyTypeObject, restype, argtypes: var PyObject): PyBaseErrorObject =
  let dict = PyDictObject(typ.dict)
  restype = dict.getOptionalItem(newPyAscii"_restype_")
  argtypes = dict.getOptionalItem(newPyAscii"_argtypes_")
  if restype.isNil or argtypes.isNil:
    return newTypeError newPyStr(typ.name & " is not a callback type")

proc callbackAbi(typ: PyTypeObject): TABI =
  let abi = PyDictObject(typ.dict).getOptionalItem(newPyAscii"_npy_abi_")
  assert abi.ofPyIntObject
  cast[TABI](PyIntObject(abi).toSomeSignedIntUnsafe[:int])

proc callbackTrampoline(cif: var TCif, ret: pointer, args: UncheckedArray[pointer], userData: pointer) {.cdecl.} =
  let self = cast[PyCFuncObject](userData)
  var restype, argtypes: PyObject
  let exc = self.pyType.callbackSignature(restype, argtypes)
  assert exc.isNil, $exc
  let fastArgtypes = PySequence_Fast(argtypes, "callback argtypes must be a sequence")
  if fastArgtypes.isThrownException:
    zeroMem(ret, cif.rtype.size)
    return
  var pyArgs = newSeq[PyObject](int cif.nargs)
  for i in 0..<pyArgs.len:
    let argtype = PySequence_Fast_GET_ITEM(fastArgtypes, i)
    let info = ctypeInfo(argtype, allowVoidInC = false)
    if info.ffiType.isNil:
      zeroMem(ret, cif.rtype.size)
      return
    let value = FFIValue(kind: info.kind, p: args[i])
    pyArgs[i] = resultToPy(info, value, argtype)
  let value = self.callback.fastCall(pyArgs)
  if value.isThrownException:
    zeroMem(ret, cif.rtype.size)
    return
  let retInfo = ctypeInfo(restype, allowVoidInC = true)
  if retInfo.kind == ckVoid:
    return
  var resultValue: FFIValue
  let err = prepareArg(value, retInfo, resultValue)
  if not err.isNil:
    zeroMem(ret, cif.rtype.size)
    return
  copyMem(ret, resultValue.p, cif.rtype.size)

proc newPyCallback*(typ: PyTypeObject, callback: PyObject): PyObject {.raises: [].} =
  if callback.pyType.magicMethods.call.isNil:
    return newTypeError newPyStr("expected a callable, got " & callback.typeName)
  var restype, argtypes: PyObject
  retIfExc typ.callbackSignature(restype, argtypes)
  let retInfo = ctypeInfo(restype, allowVoidInC = true)
  if retInfo.ffiType.isNil:
    return unsupportedCType(restype)
  let fastArgtypes = PySequence_Fast(argtypes, "callback argtypes must be a sequence")
  retIfExc fastArgtypes
  let self = PyCFuncObject typ.tp_alloc(typ, 0)
  self.callback = callback
  self.restype = restype
  self.argtypes = argtypes
  self.ffiTypes.setLen(PySequence_Fast_GET_SIZE(fastArgtypes))
  for i in 0..<self.ffiTypes.len:
    let argtype = PySequence_Fast_GET_ITEM(fastArgtypes, i)
    let info = ctypeInfo(argtype, allowVoidInC = false)
    if info.ffiType.isNil:
      return unsupportedCType(argtype)
    self.ffiTypes[i] = info.ffiType
  if prep_cif(self.cif, typ.callbackAbi, cuint self.ffiTypes.len, retInfo.ffiType, self.ffiTypes.addr0) != OK:
    return newRuntimeError newPyAscii"ffi_prep_cif failed"
  self.closure = closure_alloc(self.handle)
  if self.closure.isNil:
    return newMemoryError newPyAscii"ffi_closure_alloc failed"
  if prep_closure_loc(self.closure, self.cif, callbackTrampoline, cast[pointer](self), self.handle) != OK:
    closure_free(self.closure)
    self.closure = nil
    return newRuntimeError newPyAscii"ffi_prep_closure_loc failed"
  self

proc newCFuncType*(restype: PyObject, argtypes: openArray[PyObject], abi = DEFAULT_ABI): PyObject {.raises: [].} =
  let retInfo = ctypeInfo(restype, allowVoidInC = true)
  if retInfo.ffiType.isNil:
    return unsupportedCType(restype)
  for argtype in argtypes:
    if ctypeInfo(argtype, allowVoidInC = false).ffiType.isNil:
      return unsupportedCType(argtype)
  let typ = newPyType[PyCFuncObject]("CFunctionType", base = pyCFuncObjectType)
  typ.pyType = pyTypeObjectType
  typ.kind = PyTypeToken.Type
  typ.magicMethods.New = pyCFuncObjectType.magicMethods.New
  typ.typeReady true
  let dict = PyDictObject typ.dict
  dict[newPyAscii"_restype_"] = restype
  dict[newPyAscii"_argtypes_"] = newPyTuple(argtypes)
  dict[newPyAscii"_npy_abi_"] = newPyInt(ord abi)
  typ

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
    retIfExc prepareArg(arg, argInfo, argValues[i])
    argPointers[i] = argPtr(argValues[i])

  var cif: TCif
  if prep_cif(cif, DEFAULT_ABI, cuint args.len, retInfo.ffiType,
      ffiTypes.addr0) != OK:
    return newRuntimeError newPyAscii"ffi_prep_cif failed"

  var resultValue = FFIValue(kind: retInfo.kind)
  resultValue.p = alloc retInfo.ffiType.size
  resultValue.pIsAlloced = true

  call(cif, cast[proc(){.cdecl.}](self.handle), argPtr(resultValue),
      argPointers.addr0)
  resultToPy(retInfo, resultValue, restype)

