
import std/strformat
import ../[
  pyobject,
  tupleobjectImpl,
  dictobject,
  exceptions,
  stringobject,
  noneobject,
  #listobject,
]

proc excess_args(args: PyTupleObject, kwds: PyDictObject): bool =
  args.len != 0 or
        (not kwds.isNil and ofPyDictObject(kwds) and kwds.len != 0)

template wrapAsBltinFunc(fun): untyped{.dirty.} =
  proc `fun wrap`*(args: openArray[PyObject]; kwargs: PyObject): PyObject{.pyCFuncPragma.} =
    fun(PyTypeObject args[0], newPyTuple args[1..^1], PyDictObject kwargs)
template wrapAsBinFunc(fun): untyped{.dirty.} =
  proc `fun wrap`*(self: PyObject, args: openArray[PyObject]; kwargs: PyObject): PyObject{.pyCFuncPragma.} =
    fun(self, newPyTuple args, PyDictObject kwargs)


proc object_new*(typ: PyTypeObject, args: PyTupleObject, kwds: PyDictObject): PyObject{.pyCFuncPragma.}
proc object_init*(obj: PyObject, args: PyTupleObject, kwds: PyDictObject): PyObject{.pyCFuncPragma.}

wrapAsBinFunc object_init
wrapAsBltinFunc object_new

template check(ascii, s) =
  if excess_args(args, kwds):
    if typ.magicMethods.New == object_new_wrap:
      return newTypeError newPyAscii ascii
    if typ.magicMethods.init != object_init_wrap:
      return newTypeError newPyStr s

proc object_init*(obj: PyObject, args: PyTupleObject, kwds: PyDictObject): PyObject{.pyCFuncPragma.} =
  let typ = obj.pyType
  check(
    "object.__init__() takes exactly one argument (the instance to initialize)",
    &"{typ.name:.200s}.__init__() takes exactly one argument (the instance to initialize)"
  )
  pyNone

proc object_new*(typ: PyTypeObject, args: PyTupleObject, kwds: PyDictObject): PyObject{.pyCFuncPragma.} =
  check(
    "object.__new__() takes exactly one argument (the type to instantiate)",
    &"{typ.name:.200s}() takes no arguments"
  )

  when compiles(tp.tp_flags) or compiles(tp.flags):
    if typ.tp_flags & Py_TPFLAGS_IS_ABSTRACT:

      #[ Compute "', '".join(sorted(type.__abstractmethods__))
          into joined. ]#
      let abstract_methods = type_abstractmethods(typ, nil)
      retIfExc abstract_methods
      let sorted_methods = PySequence_List(abstract_methods)

      retIfExc sorted_methods

      retIfExc tpMethod(List, sort) sorted_methods

      let comma_w_quotes_sep = newPyAscii("', '")
      #retIfExc comma_w_quotes_sep.isThrownException
      let joined = tpMethod(string, join)(comma_w_quotes_sep, sorted_methods)
      retIfExc joined
      let method_count = len(sorted_methods)

      let s = if method_cound>1: "s" else: ""
      return newTypeError(
        &"Can't instantiate abstract class {typ.name:s} "&
                    "without an implementation for abstract method{s} '{joined:U}'"
      )
  typ.tp_alloc(typ, 0)

