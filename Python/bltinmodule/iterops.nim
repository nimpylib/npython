

import ../getargs/[
  dispatch,
  kwargs,
]
import ../../Objects/[
  pyobject,
  tupleobjectImpl,
  exceptions,
  noneobject,
  stringobject,
  boolobjectImpl,
  pyobject_apis/compare,
]
import ../../Objects/listobject/sort
import ../../Objects/abstract/[
  iter,
  sequence/list,
]
import ../call
import ../getargs/[tovals,]
import ./utils


proc sorted*(sequ: PyObject, key: PyObject = pyNone, reversed = false): PyObject{.bltin_clinicGen.} =
  result = PySequence_List(sequ)
  retIfExc result
  let newlist = PyListObject result
  retIfExc newlist.sort(key, reversed)
  return newlist


proc min_max(args: openArray[PyObject], keyfunc, defaultval: PyObject, op: PyCompareOp, name: string): PyObject =
  var nargs = args.len
  if nargs == 0:
    return newTypeError newPyAscii name&" expected at least 1 argument, got 0"

  # (kwnames != NULL && !_PyArg_ParseStackAndKeywords(args + nargs, 0, kwnames, _parser, &keyfunc, &defaultval)):

  let positional = nargs > 1 # False iff nargs == 1
  if positional and not defaultval.isNil:
    return newTypeError newPyAscii(
                    "Cannot specify a default for "&name&"() with multiple "&
                    "positional arguments")

  var it: PyObject
  if not positional:
    it = PyObject_GetIter(args[0])
    retIfExc it

  var keyfunc = keyfunc
  if keyfunc.isPyNone: keyfunc = nil

  var
    item,
      maxitem, # the result
      maxval: PyObject  # the value associated with the result
    i = 0
  while true:
    if positional:
      if nargs <= 0:
        nargs.dec
        break
      nargs.dec
      item = args[i]
      i.inc
    else:
      let res = PyIter_NextItem(it, item)
      case res
      of Error: return item
      of Missing:
        break
      of Get: discard

    # get the value from the key function
    var val: PyObject
    if not keyfunc.isNil:
      val = keyfunc.call(item)
      retIfExc val
    # no key function; the value is the item
    else:
      val = item

    # maximum value and item are unset; set them
    if maxval.isNil:
      maxitem = item
      maxval = val
    # maximum value and item are set; update them as necessary
    else:
      var resb: bool
      let res = PyObject_RichCompareBool(val, maxval, op, resb)
      retIfExc res
      if resb:
        maxval = val
        maxitem = item

  if maxval.isNil:
    assert maxitem.isNil
    if not defaultval.isNil:
      maxitem = defaultval
    else:
      return newValueError newPyAscii name &
                      "() iterable argument is empty"
  return maxitem

template gen_any_all(any_all; bOnAbort, bOnFinal){.dirty.} =
  proc any_all*(iterable: PyObject): PyObject{.bltin_clinicGen.} =
    let it = PyObject_GetIter(iterable)
    retIfExc it
    let iternext = it.getMagic(iternext)
    var
      item: PyObject
      b: bool
      errOccurred = false
    while true:
      item = iternext(it)
      errOccurred = item.isThrownException
      if errOccurred: break
      retIfExc PyObject_IsTrue(item, b)
      if b == bOnAbort:
        return `py bOnAbort Obj`

    if errOccurred:
      if not item.isStopIter:
        return item
    return `py bOnFinal Obj`

gen_any_all any, true, false
gen_any_all all, false, true


template gen_min_max(f, op){.dirty.} =
  proc `builtin f`*(args: varargs[PyObject], kwargs: PyObject): PyObject{.pyCFuncPragma.} =
    const name = astToStr(f)
    var key, default: PyObject
    retIfExc PyArg_UnpackKeywordsTo(name, PyDictObject kwargs, key, default)
    min_max(args, key, default, op, name)

# AC: cannot convert yet, waiting for *args support
#proc min*(args: varargs[PyObject], keyfunc: PyObject = nil, defaultval: PyObject = nil): PyObject {.bltin_clinicGen.} =
gen_min_max min, Py_LT
gen_min_max max, Py_GT

template register_iterops* =
  bind regfunc
  regfunc sorted
  regfunc min
  regfunc max
  regfunc any
  regfunc all
