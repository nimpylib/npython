
from std/math import ceilDiv, divmod
import ./decl
#[
import ./nint_proto
import ../reimporter
]#
when true:
  import ./ops
  import ./ops_mix_nim
  import ./utils
  from ./bit_length import digitCount
  type NimInt = PyIntObject
  template newInt: NimInt = newPyIntSimple()
  # template getSize(x: NimInt): int = x.digitCount
  template fitLen(_: NimInt; _: int): bool = true

  type PyBytes = openArray[char]
  template getChar(x: PyBytes, i: int): char = x[i]
  template getInt(x: PyBytes, i: int): int = int x[i]

import pkg/nimpatch/castChar
import pkg/nimpatch/newUninit
const weridTarget = defined(js) or defined(nimscript)

func parseByteOrder*(byteorder: string): Endianness =
  if byteorder == "little": result = littleEndian
  elif byteorder == "big": result = bigEndian
  else: raise newException(ValueError, "byteorder must be either 'little' or 'big'")

template highByte(b: PyBytes, endian: Endianness, hi = b.len-1): uint8 =
  uint8:
    if endian == bigEndian : b.getChar 0
    else: b.getChar hi

template signbitSet(b: uint8): bool =
  (b and 0b1000_0000'u8) == 0b1000_0000'u8

const arrNotCvtableInt = weridTarget

when arrNotCvtableInt:
  template loopRangeWithIt(bHi: int, byteorder: Endianness, body: untyped){.dirty.} =
    if byteorder == bigEndian:
      for it{.inject.} in countdown(bHi, 0): body
    else:
      for it{.inject.} in 0 .. bHi: body

proc complement2(res: var NimInt, bLen: int) =
  ## `res = res - PyIntObject(pyIntOne shl (8 * bLen))`
  let shiftBits = 8 * bLen
  let (wordShift, bitShift) = divmod(shiftBits, digitBits)

  if res.digits.len <= wordShift:
    res.digits.setLen(wordShift + 1)
  var maxIdx = wordShift
  if res.digits.len > 0:
    maxIdx = max(res.digits.len - 1, wordShift)
  let base = SDigit(1) shl digitBits
  var borrow: SDigit = 0
  for i in 0..maxIdx:
    let powDigit =
      if i == wordShift:
        SDigit(1) shl bitShift
      else:
        0
    var diff = powDigit - SDigit(res.digits[i]) - borrow
    if diff < 0:
      diff += base
      borrow = 1
    else:
      borrow = 0
    res.digits[i] = Digit(diff)
  res.normalize()
  if res.digits.len == 0:
    res.sign = Zero
  else:
    res.sign = Negative

proc add_from_bytes(res: var NimInt, bytes: PyBytes, byteorder: Endianness, signed=false) =
  assert res.digitCount == 0

  let bLen = bytes.len
  if bLen == 0:
    return
  if not res.fitLen bLen:
    raise newException(OverflowDefect, "Currently NimInt cannot hold so many bytes")

  static:assert digitBits mod 8 == 0
  const digitBytes = digitBits div 8
  let L = bytes.len
  let (q, r) = divmod(L, digitBytes)

  let bHi = L - 1
  let cisEndian = byteorder == littleEndian
  template loopWithIt(r, i) =
    var curDigit: Digit = 0
    let itot = i*digitBytes
    when arrNotCvtableInt:
      for it{.inject.} in countdown(r-1, 0):
        let byteIndex =
          if cisEndian:
            itot + it
          else:
            bHi - (itot + it)
        curDigit = (curDigit shl 8
          ) or (bytes.getInt(byteIndex).Digit)
    else:
      if cisEndian:
        copyMem(addr curDigit, addr bytes[itot], r)
      else:
        var holder: array[digitBytes, char]
        let byteIdx = bHi - (itot + r) + 1
        copyMem(addr holder[0], addr bytes[byteIdx], r)
        var lo = 0
        var hi = r - 1
        while lo < hi:
          let tmp = holder[lo]
          holder[lo] = holder[hi]
          holder[hi] = tmp
          inc lo
          dec hi
        copyMem(addr curDigit, addr holder[0], r)

    res.digits.add curDigit
  for i in 0..<q:
    loopWithIt digitBytes, i

  if r != 0:
    loopWithIt r, q

  res.normalize()
  if res.digits.len == 0:
    res.sign = Zero
  else:
    res.sign = Positive
  if signed and bytes.highByte(byteorder, bHi).signbitSet():
    # we've check bytes is not empty above
    res.complement2(bLen)

proc newPyInt*(bytes: PyBytes, endianness: Endianness, signed=false): NimInt =
  result = newInt()
  result.add_from_bytes(bytes, endianness, signed)

using self: NimInt
proc to_bytes*[T: char|uint8|int8](self; length: int, endianness: Endianness, signed=false, result: var seq[T]) =
  ## EXT.
  if length < 0:
    raise newException(ValueError, "length argument must be non-negative")
  if not signed and self < 0:
    raise newException(OverflowDefect, "can't convert negative int to unsigned")

  var bitLen = 0
  if self.digits.len > 0:
    var hi = self.digits[^1]
    var hiBits = 0
    while hi > 0:
      inc hiBits
      hi = hi shr 1
    bitLen = (self.digits.len - 1) * digitBits + hiBits
  let byteLen = ceilDiv(bitLen, 8)
  if byteLen > length:
    raise newException(OverflowDefect, "int too big to convert")

  const digitBytes = digitBits div 8
  result = newSeqUninit[T](length)
  for pos in 0..<length:
    let digitIndex = pos div digitBytes
    let byteOffset = (pos mod digitBytes) * 8
    var byteVal: Digit = 0
    if digitIndex < self.digits.len:
      byteVal = (self.digits[digitIndex] shr byteOffset) and Digit(0xFF)
    if endianness == littleEndian:
      result[pos] = cast[T](byteVal)
    else:
      result[length - 1 - pos] = cast[T](byteVal)

proc to_bytes*(self; length: int, endianness: Endianness, signed=false): seq[char] =
  self.to_bytes(length, endianness, signed=signed, result=result)

proc to_bytes*(self; length=1, byteorder: string = "big", signed=false): seq[char] =
  let endianness = parseByteOrder $byteorder
  self.to_bytes(length, endianness, signed=signed, result=result)

when isMainModule:
  import std/unittest
  let b = "\xFF\xFF\xFF"
  let i = newPyInt(b, littleEndian, signed=true)
  check i == -1

  let b2 = "\x01\x02\x03\x04"
  let i2 = newPyInt(b2, bigEndian)
  check i2 == 0x01020304
  check i2.to_bytes(4, bigEndian) == @b2

  let b3 = "\x05\x04\x03\x02\x01"
  check newPyInt(b3, littleEndian) == 0x0102030405
  check newPyInt(b3, bigEndian) ==    0x0504030201
  check newPyInt(b3, littleEndian).to_bytes(5, littleEndian) == @b3

  let b4 = "\x80\x00"
  let i4 = newPyInt(b4, bigEndian, signed=true)
  check i4 == -0x8000

  let b5 = "\x00\x00\x01"
  let i5 = newPyInt(b5, bigEndian, signed=false)
  check i5 == 1

  let b6 = "\xFF\xFF\x80"
  let i6 = newPyInt(b6, littleEndian, signed=true)
  check i6 == -0x7F0001
