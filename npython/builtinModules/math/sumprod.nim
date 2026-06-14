import std/math
from pkg/pymath/isX import isfinite
from pkg/pymath/vec_op/private/dl_ops import DoubleLength, dl_mul, dl_sum
include ./comm
impObj [
  boolobject,
  iterobject,
  stringobject,
]
import ./mult_utils
impObj abstract/number
impObj abstract/iter

type TripleLength = object
  hi, lo, tiny: float

template tl_zero: TripleLength = TripleLength()

func tl_fma(x, y: float; total: TripleLength): TripleLength =
  let
    pr: DoubleLength = dl_mul(x, y)
    sm: DoubleLength = dl_sum(total.hi, pr.hi)
    r1: DoubleLength = dl_sum(total.lo, pr.lo)
    r2: DoubleLength = dl_sum(r1.hi, sm.lo)
  TripleLength(hi: sm.hi, lo: r2.hi, tiny: total.tiny + r1.lo + r2.lo)

func tl_to_d(total: TripleLength): float =
  let last = dl_sum(total.lo, total.hi)
  total.tiny + last.lo + last.hi

template long_add_would_overflow(a, b: int): bool =
  if a >= 0:
    b > int.high - a
  else:
    b < int.low - a

proc intAsLong(obj: PyObject; value: var int): bool =
  if not obj.ofExactPyIntObject:
    return false
  var overflow: bool
  value = PyIntObject(obj).asLongAndOverflow overflow
  not overflow

proc intAsDouble(obj: PyObject; value: var float): PyBaseErrorObject =
  var overflow: PyOverflowErrorObject
  value = PyIntObject(obj).toFloat overflow
  overflow

proc sumprod*(p, q: PyObject): PyObject{.pyCFuncPragma.} =
  let p_it = PyObject_GetIter(p)
  retIfExc p_it
  let q_it = PyObject_GetIter(q)
  retIfExc q_it

  result = pyIntZero
  var
    p_i, q_i: PyObject
    p_stopped, q_stopped: bool
    int_path_enabled = true
    int_total_in_use = false
    int_total = 0
    flt_path_enabled = true
    flt_total_in_use = false
    flt_total = tl_zero

  template nextPair(finished: var bool) =
    let p_res = PyIter_NextItem(p_it, p_i)
    case p_res
    of Error:
      return p_i
    of Missing:
      p_stopped = true
    of Get:
      p_stopped = false

    let q_res = PyIter_NextItem(q_it, q_i)
    case q_res
    of Error:
      return q_i
    of Missing:
      q_stopped = true
    of Get:
      q_stopped = false

    if p_stopped != q_stopped:
      return newValueError newPyAscii"Inputs are not the same length"
    finished = p_stopped and q_stopped

  template flushAccum(totalObj) =
    let new_total = PyNumber_Add(result, totalObj)
    retIfExc new_total
    result = new_total

  template finalizeIntPath() =
    int_path_enabled = false
    if int_total_in_use:
      flushAccum(newPyInt int_total)
      int_total = 0
      int_total_in_use = false

  template finalizeFltPath() =
    flt_path_enabled = false
    if flt_total_in_use:
      flushAccum(newPyFloat tl_to_d(flt_total))
      flt_total = tl_zero
      flt_total_in_use = false

  template genericProductAdd() =
    let term = PyNumber_Mul(p_i, q_i)
    retIfExc term
    let new_total = PyNumber_Add(result, term)
    retIfExc new_total
    result = new_total

  while true:
    var finished = false
    nextPair(finished)

    if int_path_enabled:
      var int_p, int_q: int
      if not finished and intAsLong(p_i, int_p) and intAsLong(q_i, int_q) and
          not check_mult_overflow(int_p, int_q):
        let int_prod = int_p *% int_q
        if not long_add_would_overflow(int_total, int_prod):
          int_total += int_prod
          int_total_in_use = true
          continue
      finalizeIntPath()

    if flt_path_enabled:
      block flt_path:
        if not finished:
          var flt_p, flt_q: float
          let
            p_type_float = p_i.ofExactPyFloatObject
            q_type_float = q_i.ofExactPyFloatObject
          if p_type_float and q_type_float:
            flt_p = PyFloatObject(p_i).asDouble
            flt_q = PyFloatObject(q_i).asDouble
          elif p_type_float and (q_i.ofExactPyIntObject or q_i.ofExactPyBoolObject):
            flt_p = PyFloatObject(p_i).asDouble
            let exc = intAsDouble(q_i, flt_q)
            if exc.isNil.not:
              finalizeFltPath()
              break flt_path
          elif q_type_float and (p_i.ofExactPyIntObject or p_i.ofExactPyBoolObject):
            flt_q = PyFloatObject(q_i).asDouble
            let exc = intAsDouble(p_i, flt_p)
            if exc.isNil.not:
              finalizeFltPath()
              break flt_path
          else:
            finalizeFltPath()
            break flt_path

          let new_flt_total = tl_fma(flt_p, flt_q, flt_total)
          if isfinite(new_flt_total.hi):
            flt_total = new_flt_total
            flt_total_in_use = true
            continue
        finalizeFltPath()

    if finished:
      return
    genericProductAdd()

implMathModuleMethod sumprod(p, q): sumprod(p, q)

