import std/hashes
import ./pyobject 
import ./[
  exceptions, stringobject, boolobjectImpl,
]
import ./numobjects/intobject/[decl, ops]
import ../Utils/utils

proc unhashable*(obj: PyObject): PyTypeErrorObject = newTypeError newPyAscii(
  "unhashable type '" & obj.pyType.name & '\''
)

proc rawHash*(obj: PyObject): Hash =
  ## for type.__hash__
  hash(obj.id)

var curHashExc{.threadvar.}: PyBaseErrorObject
proc popCurHashExc(): PyBaseErrorObject =
  ## never returns nil, assert exc happens
  assert not curHashExc.isNil
  result = curHashExc
  curHashExc = nil

proc PyObject_Hash*(obj: PyObject, exc: var PyBaseErrorObject): Hash =
  exc = nil
  let fun = obj.pyType.magicMethods.hash
  if fun.isNil:
    #PY-DIFF: we don't
    #[
    ```c
    if (!_PyType_IsReady(tp)) {
      if (PyType_Ready(tp) < 0)
       ...
    ```
    ]#
    # as we only allow declare python type via `declarePyType`
    return rawHash(obj)
  else:
    let retObj = fun(obj)
    if retObj.ofPyIntObject:
      # ref CPython/Objects/typeobject.c:slot_tp_hash
      let i = PyIntObject(retObj)
      var ovf: bool
      result = i.asLongAndOverflow(ovf)
      if unlikely ovf:
        result = hash(i)
    elif retObj.isThrownException:
      exc = PyBaseErrorObject retObj
    else:
      exc = unhashable obj

proc PyObject_Hash*(obj: PyObject): PyObject =
  var exc: PyBaseErrorObject
  let h = PyObject_Hash(obj, exc)
  if exc.isNil: newPyInt h
  else: exc

template signalDictError(msg) =
  if not curHashExc.isNil:
    raise newException(DictError, msg)

# hash functions for py objects
# raises an exception to indicate type error. Should fix this
# when implementing custom dict
proc hash*(obj: PyObject): Hash = 
  ## inner usage for dictobject.
  ## 
  ## .. warning:: remember wrap around `handleHashExc` to handle exception
  result = PyObject_Hash(obj, curHashExc)
  signalDictError "hash"

template handleHashExc*(handleExc; body) =
  ## to handle exception from `hash`_
  bind popCurHashExc, DictError
  try: body
  except DictError: handleExc popCurHashExc()
template retE(e) = return e
template handleHashExc*(body) =
  ## return exception
  bind retE
  handleHashExc retE, body

proc rawEq*(obj1, obj2: PyObject): bool =
  ## for type.__eq__
  obj1.id == obj2.id

proc PyObject_Eq*(obj1, obj2: PyObject, exc: var PyBaseErrorObject): bool =
  ## XXX: CPython doesn't define such a function, it uses richcompare (e.g. `_Py_BaseObject_RichCompare`)
  ##
  ## .. note:: `__eq__` is not required to return a bool,
  ##   so this calls `PyObject_IsTrue`_ on result 
  exc = nil
  let fun = obj1.pyType.magicMethods.eq
  if fun.isNil:
    return rawEq(obj1, obj2)
  else:
    let retObj = fun(obj1, obj2)
    if retObj.isThrownException:
      exc = PyBaseErrorObject retObj
      return
    exc = PyObject_IsTrue(retObj, result)

proc `==`*(obj1, obj2: PyObject): bool {. inline, cdecl .} =
  ## inner usage for dictobject.
  ## 
  ## .. warning:: remember wrap around `handleHashExc` to handle exception
  result = PyObject_Eq(obj1, obj2, curHashExc)
  signalDictError "eq"
