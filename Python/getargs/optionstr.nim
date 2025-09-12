
import ../../Objects/[
  pyobjectBase, stringobject, exceptions, noneobject,
]
import ../../Objects/stringobject/strformat

proc getOptionalStr*(argname: string; sobj: var PyObject; res: var string): PyBaseErrorObject =
  ## to unpack keyword arg, for Optional[str]
  ## `res` won't be overwritten if `sobj` is not given as a str object
  if sobj.isPyNone: sobj = nil
  if not sobj.isNil:
    if not sobj.ofPyStrObject:
      let s = newPyStr&"{argname} must be None or a string, not {sobj.typeName:.200s}"
      retIfExc s
      return newTypeError PyStrObject s
    (res, _) = sobj.PyStrObject.asUTF8AndSize()

