
import std/macros
import ./[
  pyobject, exceptions,
  boolobject, stringobject,
]
import ./numobjects/intobject/decl
import ../Utils/trans_imp
impExp tupleobject,
  decl

proc isPyTrueObj*(obj: PyObject): bool = system.`==`(obj, pyTrueObj)  ## inner
proc tupleSeqToString*(ss: openArray[UnicodeVariant]): UnicodeVariant =
  ## inner
  ## one-element tuple must be out as "(1,)"
  result = newUnicodeUnicodeVariant "("
  case ss.len
  of 0: discard
  of 1:
    result.unicodeStr.add ss[0].toRunes
    result.unicodeStr.add ','
  else:
    result.unicodeStr.add ss.joinAsRunes", "
  result.unicodeStr.add ')'

template genCollectMagics*(items,
  implNameMagic,
  ofPyNameObject, PyNameObject,
  mutRead, mutReadRepr, seqToStr){.dirty.} =
  bind newPyInt, pyTrueObj, pyFalseObj, isPyTrueObj
  bind newPyString, PyStrObject, UnicodeVariant
  bind isThrownException, errorIfNotString

  template len*(self: PyNameObject): int = self.items.len
  template `[]`*(self: PyNameObject, i: int): PyObject = self.items[i]
  iterator items*(self: PyNameObject): PyObject =
    for i in  self.items: yield i

  implNameMagic contains, mutRead:
    for item in self:
      let retObj =  item.callMagic(eq, other)
      if isThrownException(retObj):
        return retObj
      if isPyTrueObj(retObj):
        return pyTrueObj
    return pyFalseObj


  implNameMagic repr, mutReadRepr:
    var ss: seq[UnicodeVariant]
    for item in self:
      var itemRepr: PyStrObject
      let retObj = item.callMagic(repr)
      errorIfNotString(retObj, "__repr__")
      itemRepr = PyStrObject(retObj)
      ss.add itemRepr.str
    return newPyString(seqToStr(ss))


  implNameMagic len, mutRead:
    newPyInt(self.len)


methodMacroTmpl(Tuple)
genCollectMagics items,
  implTupleMagic,
  ofPyTupleObject, PyTupleObject,
  [], [reprLock],
  tupleSeqToString
