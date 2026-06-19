template implArrayCData*() {.dirty.} =
  declarePyType Array(base(CData), typeName("_Array")):
    data: pointer
    size: int
    ownsData: bool
    keepalive: PyObject

  type ArrayTypeCacheEntry = tuple[
    target: PyTypeObject,
    length: int,
    arrayType: PyTypeObject,
  ]
  var arrayTypeCache: seq[ArrayTypeCacheEntry]

  proc ctypeSizeUnsafe(typ: PyTypeObject): int {.raises: [].} =
    var cur = typ
    while not cur.isNil:
      if not cur.dict.isNil and cur.dict.ofPyDictObject:
        let size = PyDictObject(cur.dict).getOptionalItem(ctypeSizeAttrName)
        if not size.isNil and size.ofPyIntObject:
          return PyIntObject(size).toSomeSignedIntUnsafe[:int]
      cur = cur.base

  proc arrayItemType*(typ: PyTypeObject): PyTypeObject {.raises: [].} =
    let attr = newPyAscii "_type_"
    var cur = typ
    while not cur.isNil:
      if not cur.dict.isNil and cur.dict.ofPyDictObject:
        let item = PyDictObject(cur.dict).getOptionalItem(attr)
        if not item.isNil and item.ofPyTypeObject:
          return PyTypeObject(item)
      cur = cur.base

  proc arrayLength*(typ: PyTypeObject): int {.raises: [].} =
    let attr = newPyAscii "_length_"
    var cur = typ
    while not cur.isNil:
      if not cur.dict.isNil and cur.dict.ofPyDictObject:
        let item = PyDictObject(cur.dict).getOptionalItem(attr)
        if not item.isNil and item.ofPyIntObject:
          return PyIntObject(item).toSomeSignedIntUnsafe[:int]
      cur = cur.base
    -1

  proc isSimpleCDataType(typ: PyTypeObject): bool {.raises: [].} =
    var cur = typ
    while not cur.isNil:
      if cur.isType pySimpleCDataObjectType:
        return true
      cur = cur.base

  proc isArrayType(typ: PyTypeObject): bool {.raises: [].} =
    var cur = typ
    while not cur.isNil:
      if cur.isType pyArrayObjectType:
        return true
      cur = cur.base

  proc arrayTypeName(target: PyTypeObject; length: int): string {.raises: [].} =
    target.name & "_Array_" & $length

  proc ARRAY*(target: PyTypeObject; length: int): PyObject {.raises: [].} =
    if not target.isCDataType:
      return newTypeError newPyStr("must be a ctypes type, not " & target.name)
    if length < 0:
      return newValueError newPyAscii"Array length must be >= 0"

    for entry in arrayTypeCache:
      if entry.target.isType(target) and entry.length == length:
        return entry.arrayType

    let itemSize = target.ctypeSizeUnsafe
    if itemSize < 0:
      return newValueError newPyAscii"ctypes item size must be >= 0"

    let typ = newPyType[PyArrayObject](arrayTypeName(target, length),
                                       base = pyArrayObjectType)
    typ.pyType = pyTypeObjectType
    typ.kind = PyTypeToken.Type
    typ.magicMethods.New = pyArrayObjectType.magicMethods.New
    typ.typeReady true
    let dict = PyDictObject typ.dict
    dict[newPyAscii"_type_"] = target
    dict[newPyAscii"_length_"] = newPyInt length
    dict[ctypeSizeAttrName] = newPyInt(itemSize * length)
    arrayTypeCache.add (target, length, typ)
    typ

  proc arrayFromTypeMul(lhs, rhs: PyObject): PyObject {.pyCFuncPragma.} =
    if lhs.ofPyTypeObject and rhs.ofPyIntObject:
      let typ = PyTypeObject(lhs)
      if typ.isCDataType:
        return ARRAY(typ, PyIntObject(rhs).toSomeSignedIntUnsafe[:int])
    if rhs.ofPyTypeObject and lhs.ofPyIntObject:
      let typ = PyTypeObject(rhs)
      if typ.isCDataType:
        return ARRAY(typ, PyIntObject(lhs).toSomeSignedIntUnsafe[:int])
    pyNotImplemented

  proc newPyArray*(typ: PyTypeObject): PyObject {.raises: [].} =
    let size = typ.ctypeSizeUnsafe
    if size < 0:
      return newValueError newPyAscii"ctypes array size must be >= 0"
    result = typ.tp_alloc(typ, 0)
    let arr = PyArrayObject(result)
    arr.size = size
    arr.ownsData = true
    arr.data =
      if size == 0: nil
      else: alloc0(size)

  proc destroyArrayData(self: PyArrayObject) {.raises: [].} =
    if self.ownsData and not self.data.isNil:
      dealloc self.data
    self.data = nil
    self.size = 0
    self.ownsData = false
    self.keepalive = nil

  proc itemAddress(self: PyArrayObject; index: int): pointer {.raises: [].} =
    let itemType = self.pyType.arrayItemType
    if itemType.isNil:
      return nil
    let itemSize = itemType.ctypeSizeUnsafe
    cast[pointer](cast[int](self.data) + index * itemSize)

  proc normalizeArrayIndex(self: PyArrayObject; index: int; normalized: var int): PyObject {.raises: [].} =
    let length = self.pyType.arrayLength
    normalized = index
    if normalized < 0:
      normalized += length
    if normalized < 0 or normalized >= length:
      return newIndexError newPyAscii"invalid index"
    pyNone

  proc arrayItem(self: PyArrayObject; index: int): PyObject {.raises: [].} =
    var index = index
    retIfExc self.normalizeArrayIndex(index, index)
    let itemType = self.pyType.arrayItemType
    if itemType.isNil:
      return newTypeError newPyAscii"ctypes array has no _type_"

    let obj = itemType.tp_alloc(itemType, 0)
    let src = self.itemAddress(index)
    if obj.ofPySimpleCDataObject:
      copyMem(PyCDataObject(obj).addressof, src, itemType.ctypeSizeUnsafe)
      return PySimpleCDataObject(obj).value

    if obj.ofPyArrayObject:
      let arr = PyArrayObject(obj)
      arr.size = itemType.ctypeSizeUnsafe
      arr.data = src
      arr.ownsData = false
      arr.keepalive = self
      return arr

    if obj.ofPyCDataObject:
      copyMem(PyCDataObject(obj).addressof, src, itemType.ctypeSizeUnsafe)
      return obj

    newNotImplementedError newPyStr("ctypes array item type not supported: " &
      itemType.name)

  proc setArrayItem(self: PyArrayObject; index: int; value: PyObject): PyObject {.raises: [].} =
    var index = index
    retIfExc self.normalizeArrayIndex(index, index)
    let itemType = self.pyType.arrayItemType
    if itemType.isNil:
      return newTypeError newPyAscii"ctypes array has no _type_"

    let dst = self.itemAddress(index)
    if itemType.isCDataType and value.ofPyCDataObject and value.pyType.isType(itemType):
      copyMem(dst, PyCDataObject(value).addressof, itemType.ctypeSizeUnsafe)
      return pyNone

    if itemType.isSimpleCDataType:
      let obj = itemType.tp_alloc(itemType, 0)
      let simple = PySimpleCDataObject(obj)
      retIfExc simple.setValue(value)
      copyMem(dst, simple.addressof, itemType.ctypeSizeUnsafe)
      return pyNone

    if itemType.isArrayType:
      return newTypeError newPyStr("expected " & itemType.name & " instance, got " &
        value.typeName)

    newNotImplementedError newPyStr("ctypes array item type not supported: " &
      itemType.name)

  method addressof*(self: PyArrayObject): pointer {.raises: [].} =
    self.data

  implArrayMagic New(tp: PyTypeObject, *values):
    let length = tp.arrayLength
    if length < 0:
      return newTypeError newPyStr(tp.name & " has no _length_")
    if values.len > length:
      return newIndexError newPyAscii"invalid index"

    result = newPyArray(tp)
    retIfExc result
    let arr = PyArrayObject(result)
    for i, value in values:
      retIfExc arr.setArrayItem(i, value)

  implArrayMagic del:
    self.destroyArrayData
    pyNone

  implArrayMagic len:
    newPyInt self.pyType.arrayLength

  implArrayMagic repr:
    newPyStr self.typeName & "()"

  proc getitemPyArrayObjectMagic*(selfObj, indexObj: PyObject): PyObject {.pyCFuncPragma.} =
    let self = PyArrayObject(selfObj)
    if not indexObj.ofPyIntObject:
      return newTypeError newPyAscii"array indices must be integers"
    self.arrayItem(PyIntObject(indexObj).toSomeSignedIntUnsafe[:int])

  proc setitemPyArrayObjectMagic*(selfObj, indexObj, value: PyObject): PyObject {.pyCFuncPragma.} =
    let self = PyArrayObject(selfObj)
    if not indexObj.ofPyIntObject:
      return newTypeError newPyAscii"array indices must be integers"
    self.setArrayItem(PyIntObject(indexObj).toSomeSignedIntUnsafe[:int], value)

  pyArrayObjectType.magicMethods.getitem = getitemPyArrayObjectMagic
  pyArrayObjectType.magicMethods.setitem = setitemPyArrayObjectMagic
  pyTypeObjectType.magicMethods.mul = arrayFromTypeMul
  pyTypeObjectType.magicMethods.imul = arrayFromTypeMul
