
proc check_mult_overflow*(a, b: int): bool =
  ## `_check_long_mult_overflow`
  #[
    The native long product x*y is either exactly right or *way* off, being
    just the last n bits of the true product, where n is the number of bits
    in a long (the delivered product is the true product plus i*2**n for
    some integer i).

    The native double product (double)x * (double)y is subject to three
    rounding errors:  on a sizeof(long)==8 box, each cast to double can lose
    info, and even on a sizeof(long)==4 box, the multiplication can lose info.
    But, unlike the native long product, it's not in *range* trouble:  even
    if sizeof(long)==32 (256-bit longs), the product easily fits in the
    dynamic range of a double.  So the leading 50 (or so) bits of the double
    product are correct.

    We check these two ways against each other, and declare victory if they're
    approximately the same.  Else, because the native long product is the only
    one that can lose catastrophic amounts of information, it's the native long
    product that must have overflowed.

  ]#

  let
    longprod = cast[int](cast[uint](a *% b))
    doubleprod = float(a) * (float)b
    doubled_longprod = (float)longprod

  if doubled_longprod == doubleprod:
    return
  let
    diff = doubled_longprod - doubleprod
    absdiff = abs diff
    absprod = abs doubleprod

  if 32.0 * absdiff <= absprod:
    return
  return true

