
include ./comm
import std/strutils
import std/hashes
impObjects [
  boolobject,
  numobjects/intobject,
]
import ../[purepaths, paths,]
implPurePathMagic hash: newPyInt self.hash

template genMethod(T, name, `==`) {.dirty.} =
  `impl T Magic` name(other):
    if not other.`ofPy T Object`:
      return pyNotImplemented
    newPyBool `==`(self, `Py T Object` other)
template genCmp(`==`, eq) {.dirty.} =  
  genMethod PurePath, eq, `==`

genCmp(`==`, eq)
genCmp(`<`, lt)
genCmp(`<=`, le)


template def4Win(def) {.dirty.} =
  def PyWindowsPathObject
  def PyPureWindowsPathObject

template defCmp(T) {.dirty.} =
  method cmpImpl(self: T, other: PyPurePathObject): int {.raises: [].} =
    cmpIgnoreCase(self.str, other.str)
def4Win defCmp

template defHash(T) {.dirty.} =
  method hashImpl(self: T): Hash {.raises: [].} = hashIgnoreCase self.str
def4Win defHash
