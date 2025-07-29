


import ./byteobjects
import ./pyobject
import ./[boolobject, numobjects, stringobject, exceptions]


export byteobjects


template impl(B, mutRead){.dirty.} =
  methodMacroTmpl(B)
  type `T B` = `Py B Object`
  `impl B Magic` eq:
    if not other.`ofPy B Object`:
      return pyFalseObj
    return newPyBool self == `T B`(other)
  `impl B Magic` len, mutRead: newPyInt self.len
  `impl B Magic` repr, mutRead: newPyAscii(repr self)
  `impl B Magic` hash: newPyInt self.items


impl Bytes, []
impl ByteArray, [mutable: read]
