
template implPointerCData*() {.dirty.} =
  declarePyType Pointer(base(CData), typeName("_Pointer")):
    c_value: pointer
    keepalive: PyObject

  type PointerTypeCacheEntry = tuple[
    target: PyTypeObject,
    pointerType: PyTypeObject,
  ]
  var pointerTypeCache: seq[PointerTypeCacheEntry]

  proc isCDataType*(typ: PyTypeObject): bool {.raises: [].} =
    var cur = typ
    while not cur.isNil:
      if cur.isType pyCDataObjectType:
        return true
      cur = cur.base

  proc isPointerType*(typ: PyTypeObject): bool {.raises: [].} =
    var cur = typ
    while not cur.isNil:
      if cur.isType pyPointerObjectType:
        return true
      cur = cur.base

  proc pointerTargetType*(typ: PyTypeObject): PyTypeObject {.raises: [].} =
    let attr = newPyAscii "_type_"
    var cur = typ
    while not cur.isNil:
      if not cur.dict.isNil and cur.dict.ofPyDictObject:
        let item = PyDictObject(cur.dict).getOptionalItem(attr)
        if not item.isNil and item.ofPyTypeObject:
          return PyTypeObject(item)
      cur = cur.base

  proc pointerTypeName(target: PyTypeObject): string {.raises: [].} =
    "LP_" & target.name

  proc newPyPointerFromAddress*(typ: PyTypeObject; address: pointer;
      keepalive: PyObject = nil): PyPointerObject {.raises: [].} =
    result = PyPointerObject typ.tp_alloc(typ, 0)
    result.c_value = address
    result.keepalive = keepalive

  proc newPyPointerTo*(obj: PyCDataObject): PyObject {.raises: [].}

  proc POINTER*(target: PyTypeObject): PyObject {.raises: [].} =
    if not target.isCDataType:
      return newTypeError newPyStr("must be a ctypes type, not " & target.name)

    for entry in pointerTypeCache:
      if entry.target.isType target:
        return entry.pointerType

    let typ = newPyType[PyPointerObject](pointerTypeName(target),
                                         base = pyPointerObjectType)
    typ.pyType = pyTypeObjectType
    typ.kind = PyTypeToken.Type
    typ.typeReady true
    let dict = PyDictObject typ.dict
    dict[newPyAscii"_type_"] = target
    dict[ctypeSizeAttrName] = newPyInt sizeof(pointer)
    pointerTypeCache.add (target, typ)
    typ

  proc newPyPointer*(typ: PyTypeObject; value: PyObject = nil): PyObject {.raises: [].} =
    let target = typ.pointerTargetType
    if target.isNil and not typ.isType pyPointerObjectType:
      return newTypeError newPyStr(typ.name & " has no _type_")

    if value.isNil or value.isPyNone:
      return newPyPointerFromAddress(typ, nil)

    if not value.ofPyCDataObject:
      return newTypeError newPyStr("expected " & target.name & " instance, got " &
        value.typeName)

    let cdata = PyCDataObject(value)
    if not target.isNil and not cdata.pyType.isType target:
      return newTypeError newPyStr("expected " & target.name & " instance, got " &
        value.typeName)
    newPyPointerFromAddress(typ, cdata.addressof, value)

  proc newPyPointerTo*(obj: PyCDataObject): PyObject =
    let typ = POINTER(obj.pyType)
    retIfExc typ
    newPyPointerFromAddress(PyTypeObject(typ), obj.addressof, obj)

  method addressof*(self: PyPointerObject): pointer {.raises: [].} =
    self.c_value.addr

  proc contents*(self: PyPointerObject): PyObject {.raises: [].} =
    if self.c_value.isNil:
      return newValueError newPyAscii"NULL pointer access"
    if not self.keepalive.isNil:
      return self.keepalive
    newNotImplementedError newPyAscii"ctypes pointer contents without keepalive"

  genProperty Pointer, "contents", contents, self.contents:
    return newNotImplementedError newPyAscii"ctypes pointer contents assignment"

  implPointerMagic New(tp: PyTypeObject, value = PyObject nil):
    newPyPointer(tp, value)

  implPointerMethod from_address(address: int), [classmethod]:
    newPyPointerFromAddress(PyTypeObject(selfNoCast), cast[pointer](address))

  implPointerMagic bool:
    newPyBool(not self.c_value.isNil)

  implPointerMagic repr:
    newPyStr(self.typeName & "(" & $cast[int](self.c_value) & ")")

