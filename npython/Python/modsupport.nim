## `args` is `NimNode` from `varargs[typed]` of macro routinue
import std/macros
import ../Objects/[
  pyobjectBase,
  noneobject,
  stringobject, numobjects, boolobject,
  tupleobject, listobject, setobject, dictobject,
]

proc isPyObjectTypeSym(ty: NimNode): bool
proc isPyObjectTypeImpl(ty: NimNode): bool =
  #if ty == PyObject.getType: return true
  # [ref ]object of Py[Xx]Object
  let obj = if ty.typeKind == ntyRef: ty[1] else: ty
  if obj.typeKind != ntyObject: return
  let impl = obj.getTypeImpl
  if impl.len > 1 and impl[1].kind == nnkOfInherit:
    let sup = impl[1][0]
    return sup.isPyObjectTypeSym
proc isPyObjectTypeSym(ty: NimNode): bool =
  if ty == bindSym"PyObject":
    return true
  isPyObjectTypeImpl ty.getType

proc isPyObject(arg: NimNode): bool =
  if arg.getTypeImpl == PyObject.getTypeImpl: return true
  arg.getType.isPyObjectTypeImpl

proc do_mktuple*(args: NimNode): NimNode
proc do_mklist(args: NimNode): NimNode
proc do_mkset(args: NimNode): NimNode
proc do_mkdict(args: NimNode): NimNode

proc do_mkvalue(arg: NimNode): NimNode =
  let ty = arg.getType
  if arg.isPyObject: arg
  else:
    template via(op): untyped =
      newCall(bindSym(astToStr op), arg)
    case ty.typeKind
    of ntyInt, ntyInt8, ntyInt16, ntyInt32, ntyInt64,
        ntyUInt, ntyUInt8, ntyUInt16, ntyUInt32, ntyUInt64:
      via newPyInt
    of ntyFloat, ntyFloat32, ntyFloat64: via newPyFloat
    of ntyBool: via newPyBool
    of ntyString, ntyCstring, ntyChar: via newPyStr
    of ntyTuple: do_mktuple(arg)
    of ntySequence: do_mklist(arg)
    of ntyArray:
      var ele: NimNode
      if arg.len > 0 and (ele=arg[0];
          ele.getType.typeKind == ntyTuple) and
          ele.kind == nnkHiddenSubConv and
          ele[1].len == 2:
        # {x: x}
        do_mkdict(arg)
      else:
        do_mklist(arg)
    of ntySet: do_mkset(arg)
    else:
      error "Unsupported type "&ty.repr&" in mkvalue"

template toPyObject(o: PyObject): PyObject = o
func basePy(a: NimNode): NimNode =
  newCall(bindSym"toPyObject", a)

#using p_format: string # XXX: Why CPython uses `ptr cstring`
template doArgToPy(arg: NimNode): NimNode = basePy do_mkvalue(arg)
template genDoColl(doname; coll; do_arg: untyped = doArgToPy){.dirty.} =
  proc doname(args: NimNode): NimNode =
    result = newCall bindSym("newPy"&coll)
    if args.len > 0:
      var res = newNimNode nnkBracket
      for arg in args:
        res.add do_arg(arg)
      result.add res

genDoColl do_mktuple, "tuple"
genDoColl do_mkset, "set"
genDoColl do_mklist, "list"
genDoColl(do_mkdict, "dict") do (arg: NimNode) -> NimNode:
  var tup = arg
  if arg.kind == nnkHiddenSubConv:
    assert arg[0].kind == nnkEmpty
    tup = arg[1]
  assert tup.len == 2
  let key = basePy do_mkvalue(tup[0])
  let val = basePy do_mkvalue(tup[1])
  result = nnkTupleConstr.newTree(key, val)

proc va_build_value(args: NimNode): NimNode =
  ## Build a tuple from `args` and return it.
  case args.len
  of 0:
    bindSym"pyNone"
  of 1:
    do_mkvalue(args[0])
  else:
    do_mktuple(args)

proc Py_VaBuildTuple*(args: NimNode): NimNode =
  ## EXT.
  do_mktuple(args)

proc Py_VaBuildValue*(args: NimNode): NimNode = va_build_value(args)
macro Py_BuildValue*(args: varargs[typed]): PyObject = Py_VaBuildValue(args)


when isMainModule:
  import ./bltinmodule

  assert Py_BuildValue() == pyNone

  let
    D = newPyDict({PyObject newPyInt 1: PyObject newPyInt 2})

  assert Py_BuildValue({1: 2}) == D
  assert Py_BuildValue({1: 2}, 3) == newPyTuple [
    D,
    newPyInt(3)
  ]

