

import std/macros
import ../../Objects/[
  pyobject, tupleobjectImpl,
  exceptions,
  stringobject,
]

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


macro unpack_stack(args; nargs; name; min, max: int, vargs#[: varargs[PyObject]]#) =
  # like unpack_stack but only for optional args
  result = newStmtList()
  result.add getAst(checkPosArgNum(name, nargs, min, max))
  template asgn(vargs, args, i): NimNode =
    newAssignment(
        vargs[i], nnkBracketExpr.newTree(args, newLit i)
      )#getAst(asgn(vargs, args, i))
  for i in 0..<vargs.len:
    let body = asgn(vargs, args, i)
    result.add quote do:
      if `nargs` > `i`: `body`

template PyArg_UnpackTuple*(args: openArray[PyObject]; name; min, max: Natural;
  vargs: varargs[PyObject],
) =
  bind unpack_stack
  let nargs = args.len
  unpack_stack(args, nargs, name, min, max, vargs)

template PyArg_UnpackTuple*(args: PyTupleObject, name; min, max: Natural;
  vargs: varargs[PyObject],
) =
  bind PyArg_UnpackTuple
  PyArg_UnpackTuple(args.items, name, min, max, vargs)


template unpackOptArgs*(args; name; min, max: Natural;
    vargs: varargs[PyObject]) =
  ## EXT.
  bind retIfExc, PyArg_UnpackTuple
  PyArg_UnpackTuple(args, name, min, max, vargs)

template unpackOptArgs*(name: string; min, max: Natural;
    vargs: varargs[PyObject]) =
  ## EXT.
  PyArg_UnpackTuple(args, name, min, max, vargs)

