## PyStructSequence

#import std/strformat as std_fmt
from std/sugar import collect
import ./stringobject/strformat
import ./[
  pyobject,
  exceptions,
  stringobjectImpl,
  dictobjectImpl,
  tupleobjectImpl,
  typeobject,
  notimplementedobject,
  noneobject,
]
import ./numobjects/intobject
import ./abstract/sequence/list
import ./pyobject_apis/[strings, gc,]
import ../Include/descrobject
import ../Include/internal/pycore_global_strings
import ../Python/getargs/[
  va_and_kw,
]
import ../Utils/utils

declarePyType StructSequence(base(Tuple), typeName("structseq")): discard


using tp: PyTypeObject
proc get_type_attr_as_size(tp; name: PyStrObject; res: var int): PyBaseErrorObject =
  let v = tp.dict.PyDictObject.getOptionalItem name
  if v.isNil:
    return newTypeError newPyStr fmt"Missed attribute '{$name.str}' of type {tp.name:s}"
  PyLong_AsSsize_t(v, res)
  #assert exc.isNil

template genGet(name, fieldId){.dirty.} =
  proc name(tp; res: var int): PyBaseErrorObject = get_type_attr_as_size(tp, pyId(fieldId), res)

genGet VISIBLE_SIZE_TP, n_sequence_fields
genGet REAL_SIZE_TP, n_fields
genGet UNNAMED_FIELDS_TP, n_unnamed_fields

template geti(name, prc){.dirty.} =
  var name: int
  retIfExc prc(typ, name)
proc newPyStructSequence*(size: int): PyStructSequenceObject =
  result = newPyStructSequenceSimple()
  result.items = collect:
    for _ in 0..<size: pyNone

proc newPyStructSequence*(typ: PyTypeObject): PyObject =
  ## PyStructSequence_New
  geti size, REAL_SIZE_TP
  geti vsize, VISIBLE_SIZE_TP
  let obj = newPyStructSequence(size)
  obj.pyType = typ
  # setLen set extra elements to `nil`
  obj.items.setLen vsize  # Hack the size of the variable object, so invisible fields don't appear to Python code
  obj

proc newPyStructSequence*(sequence: PyObject, dict: PyObject = nil, typ=pyStructSequenceObjectType): PyObject =
  ## structseq_new_impl
  geti min_len, VISIBLE_SIZE_TP
  geti max_len, REAL_SIZE_TP
  geti n_unnamed_fields, UNNAMED_FIELDS_TP

  let arg = PySequence_Fast(sequence, "constructor requires a sequence")
  retIfExc arg
  template errTpShallBe(msg) =
    return newTypeError newPyStr fmt"{typ.typeName:.500s}() takes " & msg
  if not dict.isNil and not dict.ofPyDictObject:
    errTpShallBe"a dict as second arg, if any"
  let dict = PyDictObject dict
  
  let len = PySequence_Fast_GET_SIZE(arg)
  if min_len != max_len:
    if len < min_len:
      errTpShallBe fmt"an at least {min_len}-sequence ({len}-sequence given)"
    if len > max_len:
      errTpShallBe fmt"an at most {max_len}-sequence ({len}-sequence given)"
  else:
    if len != min_len:
      errTpShallBe fmt"a {min_len}-sequence ({len}-sequence given)"
  
  result = newPyStructSequence(typ)
  retIfExc result
  let res = PyStructSequenceObject result
  for i, v in PySequence_FAST_ITEMS(arg):
    res.items[i] = v
  
  if not dict.isNil and dict.len > 0:
    var n_found_keys = 0
    for i in len..<max_len:
      let name = typ.members[i - n_unnamed_fields].name
      var ob: PyObject
      if not dict.getItemRef(newPyStr name, ob):
        ob = pyNone
      else:
        n_found_keys.inc
      res.items[i] = ob
    if dict.len > n_found_keys:
      return newTypeError newPyStr fmt"{typ.typeName:.500s}() got duplicate or unexpected field name(s)"
  else:
    for i in len..<max_len:
      res.items[i] = pyNone

implStructSequenceMagic New(typ, *a, **kw):
  retIfExc PyArg_ParseTupleAndKeywordsAs("structseq", a, kw, [], sequence, dict)
  if sequence.isNil: return newTypeError newPyAscii"structseq() missing required argument 'sequence' (pos 1)"
  newPyStructSequence(sequence, dict, PyTypeObject typ)


template reprImpl(self: PyStructSequenceObject; doReprExc): string =
  let typ = self.pyType

  let vsize = self.items.len
  let
    type_name_len = typ.name.len
    # count 5 characters per item: "x=1, "
    prealloc = (type_name_len + 1 +
                          vsize * 5 + 1)
  var writer = newStringOfCap(prealloc);

  # Write "typename("
  writer.add typ.name
  writer.add '('

  for i, value in self.items:
    if i > 0:
      # Write ", "
      writer.add ','
      writer.add ' '

    # Write name
    let name_utf8 = typ.members[i].name;
    #[if (name_utf8 == NULL) {
        PyErr_Format(PyExc_SystemError,
                      "In structseq_repr(), member %zd name is NULL"
                      " for type %.500s", i, typ->tp_name);
        goto error;
    }]#
    writer.add name_utf8

    # Write "=" + repr(value)
    writer.add '='
    assert not value.isNil

    let res = PyObject_ReprNonNil(value)
    doReprExc res
    writer.add $res
      
  writer.add ')'
  writer

proc repr*(self: PyStructSequenceObject): string =
  template doReprExc(e) =
    if e.isThrownException: unreachable()
  self.reprImpl doReprExc

method `$`*(self: PyStructSequenceObject): string{.pyCFuncPragma.} = repr self

implStructSequenceMagic repr: newPyStr reprImpl(self, retIfExc)

#implStructSequenceMagic getitem: tpMagic(Tuple, getitem)(self, other)
#implStructSequenceMagic setitem: tpMagic(Tuple, setitem)(self, arg1, arg2)

type
  Field = object
    name: string
    doc: cstring
  PyStructSequence_Desc = object
    name*: string
    doc: cstring
    fields: seq[Field]  # in_sequence & in_dict
    n_in_sequence: int

template withNewImpl(body) =
  result.name = name
  result.doc = doc
  body
  result.n_in_sequence = n_in_sequence

proc newPyStructSequence_Desc*(name: string, doc: cstring, fieldNames: openArray[string], n_in_sequence=fieldNames.len): PyStructSequence_Desc =
  withNewImpl:
    for n in fieldNames:
      result.fields.add Field(name: n)

proc newPyStructSequence_Desc*(name: string, doc: cstring, fieldNames: openArray[(string, cstring)], n_in_sequence=fieldNames.len): PyStructSequence_Desc =
  withNewImpl:
    for (n, doc) in fieldNames:
      result.fields.add Field(name: n, doc: doc)

proc newPyStructSequence_Desc*(name: string, doc: cstring, fieldNames: static openArray[(string, string)], n_in_sequence=fieldNames.len): PyStructSequence_Desc =
  withNewImpl:
    for (n, doc) in fieldNames:
      result.fields.add Field(name: n, doc: cstring doc)

const
  visible_length_key = "n_sequence_fields"
  real_length_key = "n_fields"
  unnamed_fields_key = "n_unnamed_fields"
  match_args_key = "__match_args__"
  PyStructSequence_UnnamedField = "unnamed field"  ##[ Fields with this name have only a field index, not a field name.
   They are only allowed for indices < n_visible_fields.]##

using desc: PyStructSequence_Desc
proc count_members(desc; n_unnamed_members: var int): int =
  var n_unnamed = 0
  for f in desc.fields:
    if f.name == PyStructSequence_UnnamedField:
      n_unnamed.inc
  n_unnamed_members = n_unnamed
  desc.fields.len

proc initialize_members(desc; n_members, n_unnamed_members: int): RtArray[PyMemberDef] =
  var members = initRtArray[PyMemberDef](n_members-n_unnamed_members)
  var k = 0
  for i, f in desc.fields:
    if f.name == PyStructSequence_UnnamedField:
      continue
    #[The names and docstrings in these MemberDefs are statically
    allocated so it is expected that they'll outlive the MemberDef]#
    members[k] = initPyMemberDef(f.name, akPyObject,
      offsetOf(PyStructSequenceObject, items) + i * sizeof(PyObject),
      pyMemberDefFlagsFromTags(readonly),
      f.doc)
    k.inc
  members


proc initialize_structseq_dict(desc; dict: PyDictObject, n_members, n_unnamed_members: int): PyBaseErrorObject =
  var v: PyObject
  template SET_DICT_FROM_SIZE(key, value) =
    v = newPyInt(value)
    dict[newPyAscii key] = v

  SET_DICT_FROM_SIZE(visible_length_key, desc.n_in_sequence)
  SET_DICT_FROM_SIZE(real_length_key, n_members)
  SET_DICT_FROM_SIZE(unnamed_fields_key, n_unnamed_members)

  # Prepare and set __match_args__
  var keys: seq[PyObject]
  keys = newSeq[PyObject](desc.n_in_sequence)

  for i in 0..<desc.n_in_sequence:
      if desc.fields[i].name == PyStructSequence_UnnamedField:
          continue
      let new_member = newPyStr(desc.fields[i].name)
      keys.add new_member

  dict[newPyAscii match_args_key] = newPyTuple keys

proc newPyStructSequenceType*(desc; tp_flags=0): PyObject =
  ## PyStructSequence_NewType
  var n_unnamed_members: int
  let n_members = count_members(desc, n_unnamed_members)
  let tp_members = initialize_members(desc, n_members, n_unnamed_members)

  #TODO:tp_slots
  let typ = newBltinPyType[PyStructSequenceObject](desc.name, base=pyTupleObjectType)
  typ.magicMethods.New = tpMagic(structsequence, New)
  typ.magicMethods.repr = tpMagic(structsequence, repr)
  typ.members = tp_members

  typ.typeReady()

  retIfExc initialize_structseq_dict(desc, typ.dict.PyDictObject, n_members, n_unnamed_members)
  typ

using typ: PyTypeObject
proc initialize_static_fields(typ; desc; tp_members: RtArray[PyMemberDef], tp_flags = 0) =
  typ.name = desc.name
  let n_hidden = tp_members.len - desc.n_in_sequence
  typ.tp_basicsize = sizeof((var obj: PyStructSequenceObject; obj[])) + (n_hidden - 1) * sizeof(PyObject)
  when compiles(typ.tp_itemsize):
    typ.tp_itemsize = sizeof(PyObject)
  typ.tp_dealloc = pyStructSequenceObjectType.tp_dealloc
  typ.magicMethods.repr = tpMagic(structsequence, repr)
  when compiles(typ.doc):
    typ.doc = desc.doc
  typ.base = pyTupleObjectType
  typ.bltinMethods = pyStructSequenceObjectType.bltinMethods
  typ.magicMethods.New = tpMagic(structsequence, New)
  typ.members = tp_members


proc PyStructSequence_InitBuiltinWithFlags(typ; desc; tp_flags=0): PyBaseErrorObject =
  ## `_PyStructSequence_InitBuiltinWithFlags`
  if typ.pyType.isNil:
    typ.pyType = pyTypeObjectType

  var n_unnamed_members: int
  let n_members = count_members(desc, n_unnamed_members)
  if typ.dict.isNil:  # Py_TPFLAGS_READY
    assert typ.name == default typeof(typ.name)
    assert typ.members == default typeof(typ.members)
    assert typ.base.isNil
    let tp_members = initialize_members(desc, n_members, n_unnamed_members)
    initialize_static_fields(typ, desc, tp_members, tp_flags)

    Py_SetImmortal typ
  else:
    assert typ.base == pyTupleObjectType
  
  let exc = PyStaticType_InitBuiltin(typ)
  if not exc.isNil:
    return newRuntimeError newPyStr "Can't initialize builtin type " & desc.name
  result = initialize_structseq_dict(desc, typ.dict.PyDictObject, n_members, n_unnamed_members)


template PyStructSequence_InitBuiltinWithFlags*(_; typ: PyTypeObject; desc: PyStructSequence_Desc; tp_flags: untyped): PyBaseErrorObject =
  ## `_PyStructSequence_InitBuiltinWithFlags`
  PyStructSequence_InitBuiltinWithFlags(typ, desc)


template PyStructSequence_InitBuiltin*(inter; typ: PyTypeObject; desc: PyStructSequence_Desc): PyBaseErrorObject =
  ## `_PyStructSequence_InitBuiltin`
  bind PyStructSequence_InitBuiltinWithFlags
  PyStructSequence_InitBuiltinWithFlags(typ, desc, 0)
