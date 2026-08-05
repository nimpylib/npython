
import std/sets
import ../private/utils
impObjects [
  pyobject,
  exceptions,
  dictobject,
  listobject,
  funcobject,
  iterobject,
  methodobject,
  stringobjectImpl,
  tupleobjectImpl,
  typeobjectImpl,
  descrobject,
  noneobject,
  frameobject,
]
impObjects typeobject/apis/subtype
impObjects pyobject_apis/strings
impObjects pyobject_apis/attrs
imp Python, getargs/paramsMeta
imp Python, neval_frame
imp Utils, utils
imp Include, internal/pycore_global_strings
import ../keyword/pyfuncs

declarePyType NamedTupleFieldDescriptor():
  index: int
  name: PyStrObject

implNamedTupleFieldDescriptorMagic get:
  if other.isNil:
    return self
  if not PyObject_TypeCheck(other, pyTupleObjectType):
    return newTypeError newPyAscii("descriptor requires a namedtuple instance")
  let tup = PyTupleObject other
  if self.index < 0 or self.index >= tup.items.len:
    return newAttributeError self.name
  tup.items[self.index]

implNamedTupleFieldDescriptorMagic set: retPyROAttrErr

proc newPyNamedTupleFieldDescriptor(index: int, name: PyStrObject): PyNamedTupleFieldDescriptorObject =
  result = newPyNamedTupleFieldDescriptorSimple()
  result.index = index
  result.name = name

proc namedTupleInit(self: PyObject, args: openArray[PyObject]; kwargs: PyKwArgType = nil): PyObject {.pyCFuncPragma.} =
  pyNone

proc getattrTuple(typ: PyTypeObject, s: string): PyTupleObject =
  try:
    result = PyTupleObject typ.dict.PyDictObject[newPyAscii s]
  except KeyError:
    unreachable "namedtuple type missing required attribute: " & s
proc getattr_fields(typ: PyTypeObject): PyTupleObject = getattrTuple(typ, "_fields")

const defaultsAttrName = "__new__.__defaults__"  #TODO:staticmethod.__defaults__

proc tuple_new(typ: PyTypeObject, values: sink seq[PyObject]): PyObject =
  result = typ.tp_alloc(typ, 0)
  PyTupleObject(result).items = values

proc tuple_new(typ: PyTypeObject, values: PyObject): PyObject =
  result = tuple_new(typ, @[])
  retIfExc tpMagic(Tuple, Init)(result, [values], nil)

proc namedTupleNew(args: openArray[PyObject]; kwargs: PyKwArgType = nil): PyObject {.pyCFuncPragma.} =
  if args.len < 1 or not args[0].ofPyTypeObject:
    return newTypeError newPyAscii("namedtuple.__new__ expected a type")
  let typ = PyTypeObject args[0]
  let fieldNames = typ.getattr_fields
  let fieldCount = fieldNames.len
  var values = newSeq[PyObject](fieldCount)
  var filled = newSeq[bool](fieldCount)
  if args.len - 1 > fieldCount:
    return newTypeError newPyAscii("too many positional arguments")
  for i in 1..<args.len:
    values[i - 1] = args[i]
    filled[i - 1] = true
  if not kwargs.isNil:
    let kw = PyDictObject kwargs
    var used = 0
    for idx, fieldNameObj in fieldNames:
      let fieldName = PyStrObject fieldNameObj
      var value: PyObject
      if kw.getItemRef(fieldName, value):
        if filled[idx]:
          return newTypeError newPyAscii("got multiple values for argument '" & fieldName.asUTF8 & "'")
        values[idx] = value
        filled[idx] = true
        used.inc
    if used != kw.len:
      return newTypeError newPyAscii("got an unexpected keyword argument")

  var defaultsObj: PyObject
  let ret = PyObject_GetOptionalAttr(typ, newPyAscii(defaultsAttrName), defaultsObj)
  var
    defaults: PyTupleObject
    ndefaults: int
  case ret
  of Error: return defaultsObj
  of Missing: ndefaults = 0
  of Get:
    defaults = PyTupleObject defaultsObj
    ndefaults = defaults.len

  for i in 0..<fieldCount:
    if not filled[i]:
      let defaultIdx = i - (fieldCount - ndefaults)
      if defaultIdx >= 0:
        assert ndefaults > 0
        values[i] = defaults[defaultIdx]
        filled[i] = true
  for i in 0..<fieldCount:
    if not filled[i]:
      return newTypeError newPyAscii("missing required argument")
  result = tuple_new(typ, values)

proc namedTupleRepr(selfNoCast: PyObject): PyObject {.pyCFuncPragma.} =
  #[
  self.__class__.__name__ + repr_fmt % self
  ]#
  let self = PyTupleObject selfNoCast
  var res: string
  res.add self.typeName
  res.add '('
  let field_names = self.pyType.getattr_fields
  for i, nameObj in field_names:
    if i > 0: res.add ", "
    res.add PyStrObject(nameObj).asUTF8
    res.add '='
    let it = PyObject_ReprNonNil self.items[i]
    retIfExc it
    res.add PyStrObject(it).asUTF8
  res.add ')'
  newPyStr res


proc normalizeNamedTupleDefaults(defaults: PyObject, fieldCount: int, res: var seq[PyObject]): PyBaseErrorObject =
  if defaults.isPyNone: return
  if defaults.ofPyTupleObject:
    res = PyTupleObject(defaults).items
  else:
    pyForIn item, defaults:
      retIfExc item
      res.add item
  if res.len > fieldCount:
    return newTypeError newPyAscii("Got more default values than field names")

proc normalizeNamedTupleFields(name: PyStrObject, fieldNames: openArray[PyStrObject], rename: bool, res: var seq[PyStrObject]): PyBaseErrorObject =
  let L = fieldNames.len
  var seen = initHashSet[PyStrObject](L)
  res = newSeqOfCap[PyStrObject](L)
  template retValErr(msgPre) =
    return newValueError newPyAscii(msgPre & ": '" & name.repr & "'")
  template ifRetValErr(cond, msgPre) =
    if cond: retValErr msgPre
  template check(name) =
    ifRetValErr not name.isidentifier(), "Type names and field names must be valid identifiers"
    ifRetValErr iskeyword(name), "Type names and field names cannot be a keyword"
  check name
  for i, name in fieldNames:
    let nFieldName: PyStrObject =
      if rename:
        if (not name.isidentifier() or
            iskeyword(name) or
            name.startswith('_') or
            name in seen
        ):
          newPyAscii('_' & $i)
        else:
          name
      else:
        check name
        ifRetValErr name.startswith('_'), "Field names cannot start with an underscore"
        ifRetValErr name in seen, "Encountered duplicate field name"
        name
    res.add nFieldName
    seen.incl nFieldName

  PyUnicode_InternMortal name
  for i in res: PyUnicode_InternMortal i

template genNewWithBody(T, newNamedTupleName; body) {.dirty.} =
  proc newNamedTupleName*(name: PyStrObject, field_names: T, rename{.startKwOnly.}=false,
      defaults=pyNoneObj, module=pyNoneObj): PyObject{.pyCFuncPragma.} =
    body

template genNew(T, nfieldNames;
    newNamedTupleName: untyped = newNamedTuple;
    newNamedTuplePrc: untyped = newNamedTupleName,
    ) {.dirty.} =
  genNewWithBody T, newNamedTupleName:
    newNamedTuplePrc(name, nfieldNames, rename, defaults, module)

genNewWithBody openArray[PyStrObject], newNamedTuple:
  var nFieldNames: seq[PyStrObject]
  retIfExc normalizeNamedTupleFields(name, field_names, rename, nFieldNames)
  let num_fields = nFieldNames.len
  var defaultValues: seq[PyObject]
  retIfExc normalizeNamedTupleDefaults(defaults, num_fields, defaultValues)

  let typ = newPyType[PyTupleObject](name.asUTF8, base=pyTupleObjectType)
  typ.pyType = pyTypeObjectType
  typ.kind = PyTypeToken.Tuple
  typ.tp_flags = Py_TPFLAGS.HEAPTYPE | Py_TPFLAGS.BASETYPE
  typ.tp_dealloc = pyTupleObjectType.tp_dealloc
  typ.tp_alloc = proc (self: PyTypeObject, nitems: int): PyObject {.pyCFuncPragma.} =
    let res = new PyTupleObject
    res.pyType = self
    res
  typ.magicMethods.New = namedTupleNew
  typ.magicMethods.init = namedTupleInit
  typ.magicMethods.repr = namedTupleRepr
  typ.typeReady true


  let dict = PyDictObject typ.dict

  proc namedtuple_make(cls: PyObject, args: openArray[PyObject], kw: PyObject = nil): PyObject{.pyCFuncPragma.} =
    checkArgNum 1, "_make"

    errorIfNot(Type, cls, "_make")
    let cls = PyTypeObject(cls)
    let iterable = args[0]
    result = tuple_new(cls, iterable)
    retIfExc result

    let num_fields = cls.getattr_fields.len

    let L = len(PyTupleObject(result))
    if L != num_fields:
      return newTypeError newPyAscii(fmt"Expected {num_fields} arguments, got {L}")

  proc namedtuple_asdict(selfNoCast: PyObject): PyObject{.pyCFuncPragma.} =
    let self = PyTupleObject selfNoCast
    let cls = self.pyType

    let fields = cls.getattr_fields
    let res = newPyDict(fields.len)
    for i, fieldName in fields:
      let value = self[i]
      res[PyStrObject fieldName] = value
    res
 
  proc namedtuple_replace(selfNoCast: PyObject, args: openArray[PyObject]; kwargs: PyKwArgType): PyObject {.pyCFuncPragma.} =
    checkArgNumAtMost(0, "_replace")

    let self = PyTupleObject selfNoCast
    let cls = self.pyType

    let fields = cls.getattr_fields

    var values: seq[PyObject] = self.items  # copy
    if not kwargs.isNil:
      assert kwargs.ofPyDictObject
      let kw = PyDictObject kwargs
      var rest = kw.len
      for idx, fieldNameObj in fields:
        let fieldName = PyStrObject fieldNameObj
        var value: PyObject
        if kw.getItemRef(fieldName, value):
          values[idx] = value
          rest.dec
      if rest > 0:
        return newTypeError newPyStr("Got unexpected keyword arguments: " & (
          # {list(kw)!r}
          var s: string
          s.add '['
          for k in kw:
            if s.len > 1: s.add ", "
            let ret = PyObject_ReprNonNil(k)
            retIfExc ret
            s.add PyStrObject(ret).asUTF8
          s.add ']'
          s
        ))
    result = tuple_new(cls, values)

  let makeName = newPyAscii "_make"
  dict[makeName] = newPyClassMethodDescr(typ, namedtuple_make, makeName)

  template addMethod(asdict){.dirty.} =
    let `asdict name` = newPyAscii '_' & astToStr(asdict)
    dict[`asdict name`] = newPyMethodDescr(typ, `namedtuple asdict`, `asdict name`)
  addMethod asdict
  addMethod replace

  dict[newPyAscii"__name__"] = name
  dict[newPyAscii"__qualname__"] = name
  #[ #TODO:sys._getframemodulename
  ]#
  var module = module
  if module.isPyNone:
    # XXX:In CPython, namedtuple was implemented in Python code,
    #   so depth=1
    let obj = privateGetframeNoAudit(1-1) #private_getframemodulename(1)
    if obj.isThrownException:
      # except ValueError: pass
      if not obj.isExceptionOf Value:
        return obj
    else:
      let f = PyFrameObject obj
      module = f.globals.getOptionalItem pyDUId(name)
      if module.isNil:
        module = pyId"__main__"
      else:
        retIfExc module
  if not module.isPyNone:
    dict[newPyAscii"__module__"] = module
  let newName = newPyAscii"__new__"
  let duNew = newPyStaticMethod(newPyNimFunc(namedTupleNew, newName))
  dict[newName] = duNew
  dict[newPyAscii"_fields"] = newPyTuple(nFieldNames)

  let ndefaults = defaultValues.len
  let field_defaults = newPyDict(ndefaults)
  if not defaults.isPyNone:
    retIfExc PyObject_SetAttr(typ, newPyAscii defaultsAttrName, newPyTuple(defaultValues))
    for i in 1..ndefaults:
      field_defaults[nFieldNames[^i]] = defaultValues[^i]
  dict[newPyAscii"_field_defaults"] = field_defaults
  for i, fieldName in nFieldNames:
    dict[fieldName] = newPyNamedTupleFieldDescriptor(i, fieldName)
  typ

genNew PyStrObject:
  let ls = field_names.replace(',', ' ').split()
  cast[seq[PyStrObject]](ls.items)

genNew openArray[PyObject]:
  # list(map(str, field_names))
  var nFieldNames: seq[PyStrObject]
  for i in field_names:
    let s = PyObject_Str(i)
    retIfExc s
    nFieldNames.add PyStrObject s
  nFieldNames

genNew PyObject:
  if field_names.ofPyStrObject:
    let sfield_names = PyStrObject field_names
    return newNamedTuple(name, sfield_names, rename, defaults, module)
  var nFieldNames: seq[PyStrObject]
  pyForIn i, field_names:
    let s = PyObject_Str(i)
    retIfExc s
    nFieldNames.add PyStrObject s
  nFieldNames

# gen proc named `namedtuple`
genNew PyObject, field_names,
  newNamedTupleName=namedtuple,
  newNamedTuplePrc=newNamedTuple

when isMainModule:
  impObjects [numobjects/intobject]
  imp Python, [lifecycle, pythonrun,]
  Py_Initialize()

  let d = newPyDict()
  let Point = newNamedTuple(newPyAscii"Point", [newPyAscii"x", newPyAscii"y"],
    defaults=newPyTuple([newPyInt 5]))
  assert not Point.isThrownException
  d[newPyAscii"Point"] = Point
  let Renamed = newNamedTuple(newPyAscii"Renamed", [newPyAscii"x", newPyAscii"x"],
    rename=true)
  assert not Renamed.isThrownException
  d[newPyAscii"Renamed"] = Renamed

  template runCheck(code: string) =
    let ret = PyRun_String(code, Mode.File, d, d)
    if ret.isThrownException:
      PyErr_Print(PyBaseErrorObject ret)
    assert not ret.isNil and not ret.isThrownException

  runCheck """
p = Point(2)
assert p.x == 2
assert p.y == 5
assert tuple(p) == (2, 5)
  """
  runCheck """
r = Renamed(3, 4)
assert r.x == 3
assert r._1 == 4
  """

  Py_Finalize()
