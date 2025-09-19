


import std/strformat

import ../getargs/[
  dispatch,
  kwargs,
]
import ../../Objects/[
  pyobject,
  tupleobjectImpl,
  exceptions,
  stringobject,
  byteobjects,
  numobjects,
  boolobject,
]

import ../../Objects/abstract/[
  iter, number,
]
import ../getargs/[tovals, paramsMeta]

type CompensatedSum = object
  hi, lo: float

proc newCompensatedSum(x: float): CompensatedSum = CompensatedSum(hi: x)
proc newCompensatedSum(hi, lo: float): CompensatedSum = CompensatedSum(hi: hi, lo: lo)
using total: CompensatedSum
using mtotal: CompensatedSum
using x: float
{.push cdecl, inline.}
proc `+`(total; x): CompensatedSum =
  let t = total.hi + x
  let lo = total.lo + (
    if abs(total.hi) >= abs(x):
      (total.hi - t) + x
    else:
      (x - t) + total.hi
  )
  newCompensatedSum(t, lo)
template `+=`(mtotal; x) = mtotal = mtotal + x
proc toFloat(total): float =
  if total.lo != 0 and (total.lo != Inf and total.lo != NegInf):
    return total.hi + total.lo
  total.hi
{.pop.}

proc sum*(iterable: PyObject, start{.startKwOnly.}: PyObject = nil): PyObject{.bltin_clinicGen.} =
  let iter = PyObject_GetIter iterable
  retIfExc iter

  result = start
  if result.isNil:
    result = pyIntZero
  else:
    template cantJoin(typStr, prefix) =
      return newTypeError newPyAscii "sum() can't sum "&typStr&" [use "&prefix&"''.join(seq) instead]"
    if iterable.ofPyStrObject: cantJoin "strings", ""
    if iterable.ofPyBytesObject: cantJoin "bytes", "b"
    if iterable.ofPyByteArrayObject: cantJoin "bytearray", "b"

  var item: PyObject
  when not defined(SLOW_SUM):
    #[Fast addition by keeping temporary sums in C instead of new Python objects.
    Assumes all inputs are the same type.  If the assumption fails, default
    to the more general routine.]#
    template loopAdd(cond: bool; defval; body) =
      result = nil
      while result.isNil:
        let res = PyIter_NextItem(iter, item)
        case res
        of Error: return item
        of Missing:
          return defval
        of Get: discard
        result = PyNumber_Add(body, item)
        retIfExc result
    template loopAdd(defval; body) =
      loopAdd result.isNil, defval, body
        
    if result.ofExactPyIntObject:
      var overflow: bool
      var i_result = PyIntObject(result).asLongAndOverflow overflow
      if not overflow:
        result = nil

      loopAdd newPyInt(i_result):
        if item.ofExactPyIntObject or item.ofExactPyBoolObject:
          # Single digits are common, fast, and cannot overflow on unpacking.
          var overflow = false
          let i = PyIntObject item
          let b = i.asLongAndOverflow overflow
          if not overflow and (
            if i_result >= 0:
              b <= int.high - i_result
            else:
              b >= int.low  - i_result
          ):
            i_result += b
            continue
        # Either overflowed or is not an int. Restore real objects and process normally
        newPyInt i_result
    
    if result.ofExactPyFloatObject:
      var re_sum = newCompensatedSum PyFloatObject(result).v
      loopAdd newPyFloat(re_sum.toFloat):
        if item.ofExactPyFloatObject:
          re_sum += PyFloatObject(item).v
          continue
        if item.ofPyIntObject:
          let value = PyIntObject(item).toFloat
          re_sum += value
          continue

        newPyFloat re_sum.toFloat
      

    #TODO:complex
  loopAdd true, result, item

