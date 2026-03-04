
import ../numobjects_comm
export intobject_decl except Digit, TwoDigits, SDigit, digitBits, truncate,
 IntSign
import ./[signbit, ops_toint]
import pkg/intobject/[ops_bitwise]
import ./private/dispatch

# long_invert
dispatchUnary `not`

dispatchBin `and`
dispatchBin `or`
dispatchBin `xor`

proc tooManyShiftErr: PyOverflowErrorObject =
  newOverflowError newPyAscii"too many digits in integer"


const ShiftMayOvf = int.high.BiggestUInt <= (BiggestUInt.high div digitBits)

template genShift(sh, implname; doOnShiftbyOverflow){.dirty.} =
  proc sh*(a: PyIntObject, shiftby: BiggestUInt): PyObject =
    # long_lshift_int64
    when ShiftMayOvf:
      if shiftby > BiggestUInt(int.high) * digitBits:
        doOnShiftbyOverflow

    return newPyInt sh(a.v, shiftby, false)


  proc sh*(a, b: PyIntObject): PyObject =
    if b.negative:
      return newValueError newPyAscii"negative shift count"
    var overflow: IntSign
    let shiftby = b.toSomeUnsignedInt[:BiggestUInt](overflow)
    if overflow != Zero:
      doOnShiftbyOverflow
    sh(a, shiftby)

genShift `shl`, long_lshift1:
  return tooManyShiftErr()

genShift `shr`, long_rshift1:
  if a.negative: return newPyInt -1
  else: return pyIntZero

when isMainModule:
  import ./ops
  let
    a = newPyInt "0b10"
  echo a shr 2
