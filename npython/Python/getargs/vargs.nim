

import std/macros
import ../../Objects/[
  pyobject, tupleobject,
  exceptions,
  stringobject,
]
import ./[tovalsBase, tovalUtils, paramsMeta]
export tovalsBase, paramsMeta

using args: openArray[PyObject]
using name: string
using nargs: int



proc PyArg_CheckPositional(name; nargs: int, min, max: static int): PyTypeErrorObject =
  static:
    assert min >= 0
    assert min <= max

  # inject `args.len`
  #XXX:NIM-BUG: Error: internal error: environment misses: nargs
  #  if min == 0
  #[
  type args = object
  template len(_: typedesc[args]): int =
    bind nargs
    nargs
  ]#
  let args = (len: nargs)
  when min == 0:  
    checkArgNumAtMost(max, name)
  else:
    checkArgNum(min, max, name)

template checkPosArgNum(name, nargs, min, max) =
  retIfExc PyArg_CheckPositional(name, nargs, min, max)


template PyArg_DoTupleImpl(asgn){.dirty.} =
  result = newStmtList()
  let nargs = newCall("len", args)
  result.add getAst(checkPosArgNum(name, nargs, min, max))
  for i in 0..<vargs.len:
    let v = vargs[i]
    let body = getAst(asgn(v, args, i))
    result.add quote do:
      if `nargs` > `i`: `body`

proc PyArg_VaUnpackTuple(name: NimNode; args: NimNode#[openArray[PyObject]]#; min, max: Natural;
  vargs: NimNode#[varargs[PyObject]]#,
): NimNode =
  template asgn(v, args, i): NimNode =
    v = args[i]
  PyArg_DoTupleImpl asgn

proc PyArg_VaParseTuple*(name: NimNode; args: NimNode#[openArray[PyObject]]#; min, max: Natural;
  vargs: NimNode#[varargs[auto]]#,
): NimNode =
  #TODO: current this expr is void, using `retIfExc` to `return` exception, change to become an expr
  template asgn(v, args, i): untyped =
    bind retIfExc, tovalAux
    retIfExc tovalAux(args[i], v)
  PyArg_DoTupleImpl asgn

macro unpack_stack(name: string; args; min, max: static[int], vargs#[: varargs[PyObject]]#) =
  # like CPython's unpack_stack but only for optional args
  PyArg_VaUnpackTuple(name, args, min, max, vargs)

template PyArg_UnpackTuple*(name; args: openArray[PyObject]; min, max: Natural;
  vargs: varargs[PyObject],
) =
  bind unpack_stack
  unpack_stack(name, args, min, max, vargs)

macro PyArg_ParseTuple*(name: string; args: openArray[PyObject], min, max: static Natural;
  vargs: varargs[typed],
) =
  PyArg_VaParseTuple(name, args, min, max, vargs)

template PyArg_UnpackTuple*(name; args: PyTupleObject, min, max: Natural;
  vargs: varargs[PyObject],
) =
  bind PyArg_UnpackTuple
  PyArg_UnpackTuple(name, args.items, min, max, vargs)


template unpackOptArgs*(args; name; min, max: Natural;
    vargs: varargs[PyObject]) =
  ## EXT.
  bind retIfExc, PyArg_UnpackTuple
  PyArg_UnpackTuple(name, args, min, max, vargs)

template unpackOptArgs*(name: string; min, max: Natural;
    vargs: varargs[PyObject]) =
  ## EXT.
  PyArg_UnpackTuple(name, args, min, max, vargs)

