
import ./[decl, bit_length, shift, signbit, floatinfos]

template `|=`(dest, i) = dest = dest or i

template `+`[T](a: openArray[T], i: int): openArray[T] = a.toOpenArray(i, a.high)

#[ For a nonzero PyLong a, express a in the form x * 2**e, with 0.5 <=
   abs(x) < 1.0 and e >= 0; return x and put e in *e.  Here x is
   rounded to DBL_MANT_DIG significant bits using round-half-to-even.
   If a == 0, return 0.0 and set *e = 0.  ]#

# attempt to define 2.0**DBL_MANT_DIG as a compile-time constant
when defined(js) or DBL_MANT_DIG == 53:
  const EXP2_DBL_MANT_DIG = 9007199254740992.0
else:
  proc ldexp*(arg: cdouble, exp: cint): cdouble{.importc, header: "<math.h>".}  ## inner, for PyLong_AsDouble
  let EXP2_DBL_MANT_DIG = ldexp(1.0, DBL_MANT_DIG)

const PyLong_BASE = 1i64 shl PyLong_SHIFT
proc frexp*(a: PyIntObject, e: var int64): float =
  ## `_PyLong_Frexp`
  var x_size: int
  # See below for why x_digits is always large enough.
  var x_digits: array[2 + (DBL_MANT_DIG + 1) div PyLong_SHIFT, Digit]
  #[ Correction term for round-half-to-even rounding.  For a digit x,
      "x + half_even_correction[x & 7]" gives x rounded to the nearest
      multiple of 4, rounding ties to a multiple of 8. ]#
  const half_even_correction = [0, -1, -2, 1, 0, -1, 2, 1]

  let a_size = a.digitCount()
  if a_size == 0:
    # Special case for 0: significand 0.0, exponent 0.
    e = 0
    return 0.0

  var a_bits = a.numBits()

  #[ Shift the first DBL_MANT_DIG + 2 bits of a into x_digits[0:x_size]
      (shifting left if a_bits <= DBL_MANT_DIG + 2).

      Number of digits needed for result: write // for floor division.
      Then if shifting left, we end up using

        1 + a_size + (DBL_MANT_DIG + 2 - a_bits) // PyLong_SHIFT

      digits.  If shifting right, we use

        a_size - (a_bits - DBL_MANT_DIG - 2) // PyLong_SHIFT

      digits.  Using a_size = 1 + (a_bits - 1) // PyLong_SHIFT along with
      the inequalities

        m // PyLong_SHIFT + n // PyLong_SHIFT <= (m + n) // PyLong_SHIFT
        m // PyLong_SHIFT - n // PyLong_SHIFT <=
                                        1 + (m - n - 1) // PyLong_SHIFT,

      valid for any integers m and n, we find that x_size satisfies

        x_size <= 2 + (DBL_MANT_DIG + 1) // PyLong_SHIFT

      in both cases.
  ]#
  var
    shift_digits: int
    shift_bits: int
    rem: Digit
  if a_bits <= DBL_MANT_DIG + 2:
      shift_digits = (DBL_MANT_DIG + 2 - int a_bits) div PyLong_SHIFT
      shift_bits = (DBL_MANT_DIG + 2 - int a_bits) mod PyLong_SHIFT
      x_size = shift_digits
      rem = v_lshift(x_digits + x_size, a.digits, a_size,
                      shift_bits)
      x_size += a_size
      x_digits[x_size] = rem
      x_size += 1

  else:
      shift_digits = (int)((a_bits - DBL_MANT_DIG - 2) div PyLong_SHIFT)
      shift_bits = (int)((a_bits - DBL_MANT_DIG - 2) mod PyLong_SHIFT)
      rem = v_rshift(x_digits, a.digits + shift_digits,
                      a_size - shift_digits, shift_bits)
      x_size = a_size - shift_digits
      #[ For correct rounding below, we need the least significant
          bit of x to be 'sticky' for this shift: if any of the bits
          shifted out was nonzero, we set the least significant bit
          of x. ]#
      if rem != 0:
          x_digits[0] |= 1
      else:
          while shift_digits > 0:
              shift_digits -= 1
              if a.digits[shift_digits] != 0:
                  x_digits[0] |= 1
                  break

  assert 1 <= x_size and x_size <= len(x_digits)

  # Round, and convert to double.
  x_digits[0] += Digit half_even_correction[x_digits[0] and 7]
  x_size -= 1
  var dx = float x_digits[x_size]
  while x_size > 0:
    x_size -= 1
    dx = dx * PyLong_BASE.float + x_digits[x_size].float

  # Rescale;  make correction if result is 1.0.
  dx = dx / (4.0 * EXP2_DBL_MANT_DIG)
  if dx == 1.0:
      assert a_bits < high int64
      dx = 0.5
      a_bits += 1

  e = a_bits
  return if a.negative: -dx else: dx
