
include ./comm
impObj [
  iterobject,
  stringobject,
  tupleobject,
]
impObj abstract/number
imp Python, getargs/tovals
import ./mult_utils

{.push raises: [].}
proc prodSlow(iter: PyObject, start: PyObject): PyObject =
  result = start
  pyForIn item, iter:
    result = PyNumber_Mul(result, item)
    retIfExc result

proc prod*(iter: PyObject, start: PyFloatObject): PyObject =
  let itor = getIterableNoCheck iter
  var f_result = start.asDouble
  pyForIn item, itor:
    if item.ofExactPyFloatObject:
      f_result *= PyFloatObject(item).asDouble
      continue
    if item.ofExactPyIntObject:
      var overflow: bool
      let value = PyIntObject(item).asLongAndOverflow overflow
      if not overflow:
        f_result *= float value
        continue

    let res = newPyFloat f_result
    result = PyNumber_Mul(res, item)
    retIfExc result
    break

  if result.isNil:
    result = newPyFloat f_result
    return
  return prodSlow(itor, result)

proc prod*(iter: PyObject, start = pyIntOne): PyObject =
  let itor = getIterableNoCheck iter
  var
    overflow: bool
    i_result = start.asLongAndOverflow overflow
  # Loop till non-integer element
  pyForIn item, itor:
    if item.ofExactPyIntObject:
      let b = PyIntObject(item).asLongAndOverflow overflow
      if not overflow and not check_mult_overflow(i_result, b):
        i_result = i_result *% b
        continue
    # Either overflowed or is not an int
    let res = newPyInt(i_result)
    result = PyNumber_Mul(res, item)
    retIfExc result
    break
  if result.isNil:
    result = newPyInt i_result
    return

  result = if result.ofExactPyFloatObject:
    prod(itor, PyFloatObject result)
  else:
    prodSlow(itor, result)

proc prod*(iter: PyObject, start: PyObject): PyObject =
  if start.ofExactPyIntObject:
    prod iter, PyIntObject start
  elif start.ofExactPyFloatObject:
    prod iter, PyFloatObject start
  else:
    prodSlow iter, start
{.pop.}

implMathModuleMethod prod(iter: PyObject, start = PyObject pyIntOne):
  prod(iter, start)

