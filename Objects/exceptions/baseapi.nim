
import std/strformat
import ../[pyobjectBase, stringobject]
include ./common_h
import ./base
import ../../Utils/compat
template isThrownException*(pyObj: PyObject): bool = 
  if pyObj.ofPyExceptionObject:
    cast[PyExceptionObject](pyObj).thrown
  else:
    false

template retIt = return it
template errorIfNot*(S; expect: string, pyObj: PyObject, methodName: string, doIt: untyped=retIt) = 
  if not pyObj.`ofPy S Object`:
    let typeName {. inject .} = pyObj.pyType.name
    let texp {.inject.} = expect
    let msg = methodName & fmt" returned non-{texp} (type {typeName})"
    let it {.inject.} = newTypeError newPyStr(msg)
    doIt

template errorIfNotString*(pyObj: untyped, methodName: string, doIt: untyped=retIt) = 
  errorIfNot Str, "string", pyObj, methodName, doIt

template errorIfNot*(S; pyObj: PyObject, methodName: string, doIt: untyped=retIt) = 
  errorIfNot S, astToStr(S), pyObj, methodName, doIt
template errorIfNotBool*(pyObj: PyObject, methodName: string, doIt: untyped=retIt) = 
  errorIfNot bool, pyObj, methodName, doIt

template retIfExc*(e: PyBaseErrorObject) =
  let exc = e
  if not exc.isNil:
    return exc

template retIfExc*(e: PyObject) =
  let exc = e
  if exc.isThrownException:
    return PyBaseErrorObject exc


when NPythonAsyncReadline:
  template retIfExc*(e: MayPromise[PyBaseErrorObject]) =
    let exc = mayAwait e
    if not exc.isNil:
      return mayNewPromise exc

  template retIfExc*(e: MayPromise[PyObject]) =
    let exc = mayAwait e
    if exc.isThrownException:
      return mayNewPromise PyBaseErrorObject exc

template getIterableWithCheck*(obj: PyObject): (PyObject, UnaryMethod) = 
  var retTuple: (PyObject, UnaryMethod)
  block body:
    let iterFunc = obj.getMagic(iter)
    if iterFunc.isNil:
      let msg = obj.pyType.name & " object is not iterable"
      retTuple = (newTypeError(newPyStr msg), nil)
      break body
    let iterObj = iterFunc(obj)
    let iternextFunc = iterObj.getMagic(iternext)
    if iternextFunc.isNil:
      let msg = fmt"iter() returned non-iterator of type " & iterObj.pyType.name
      retTuple = (newTypeError(newPyStr msg), nil)
      break body
    retTuple = (iterobj, iternextFunc)
  retTuple

proc errArgNumImpl(nargs: int, expected: int, preExp: string, name=cstring""): PyTypeErrorObject=
  let suffix = if expected == 1: "" else: "s"
  var msg: string
  if name != "":
    msg = fmt"{name} takes {preExp} {expected} argument{suffix} ({nargs} given)"
  else:
    msg = fmt"expected {preExp} {expected} argument{suffix}, got {nargs}"
  return newTypeError(newPyStr msg)

template errArgNum*(argsLen, expected: int; name="")=
  bind errArgNumImpl
  return errArgNumImpl(argsLen, expected, "exactly", name)

template checkArgNum*(expected: int, name="") = 
  bind errArgNum
  if args.len != expected:
    errArgNum args.len, expected, name


template checkArgNumAtLeast*(expected: int, name="") = 
  bind errArgNumImpl
  if args.len < expected:
    return errArgNumImpl(args.len, expected, "at least", name)

template checkArgNumAtMost*(expected: int, name="") =
  bind errArgNumImpl
  if args.len > expected:
    return errArgNumImpl(args.len, expected, "at most", name)

template checkArgNum*(min, max: int, name="") =
  checkArgNumAtLeast(min, name)
  checkArgNumAtMost(max, name)

proc PyErr_Format*[E: PyBaseErrorObject](exc: E, msg: PyStrObject) =
  exc.args = newPyTuple [PyObject msg]
  when compiles(exc.msg):
    exc.msg = msg
