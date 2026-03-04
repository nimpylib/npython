
import ./decl
import pkg/intobject/int_bytes
when true:
  type PyBytes = openArray[char]

export parseByteOrder

proc newPyInt*(bytes: PyBytes, endianness: Endianness, signed=false): PyIntObject =
  newPyInt newInt(bytes, endianness, signed)

using self: PyIntObject
proc to_bytes*[T: char|uint8|int8](self; length: int, endianness: Endianness, signed=false, result: var seq[T]) =
  ## EXT.
  self.v.to_bytes(length, endianness, signed=signed, result=result)  

proc to_bytes*(self; length: int, endianness: Endianness, signed=false): seq[char] =
  self.v.to_bytes(length, endianness, signed=signed)

proc to_bytes*(self; length=1, byteorder: string = "big", signed=false): seq[char] =
  self.v.to_bytes(length, byteorder, signed=signed)
