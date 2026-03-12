
import ./decl
import pkg/intobject/int_bytes
when true:
  type PyBytes = openArray[char]

export parseByteOrder

proc newPyInt*(bytes: PyBytes, endianness: Endianness, signed=false): PyIntObject =
  newPyInt newInt(bytes, endianness, signed)
proc newPyInt*[T: uint8|int8](bytes: openArray[T], endianness: Endianness, signed=false): PyIntObject =
  newPyInt newInt(bytes, endianness, signed)

using self: PyIntObject
proc to_bytes*[T: char|uint8|int8](self; length: int, endianness: Endianness, signed=false, res: var seq[T]): IntObjectToBytesError =
  ## EXT.
  self.v.to_bytes(length, endianness, signed=signed, res=res)

proc to_bytes*(self; length: int, endianness: Endianness, signed=false): seq[byte] =
  self.v.to_bytes(length, endianness, signed=signed)

proc to_bytes*(self; length=1, byteorder: string = "big", signed=false): seq[byte] =
  self.v.to_bytes(length, byteorder, signed=signed)
