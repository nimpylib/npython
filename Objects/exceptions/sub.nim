
import std/macros
import ./[
  base, utils,
]
import ../pyobject

var subErrs*{.compileTime.}: seq[string]
macro declareSubError(E, baseE) =
  let
    eeS = E.strVal & "Error"
    ee = ident eeS
    bee = ident baseE.strVal & "Error"
    typ = ident "py" & ee.strVal & "ObjectType"
    btyp = ident "py" & bee.strVal & "ObjectType"
  subErrs.add eeS
  result = quote do:
    declarePyType `ee`(base(`bee`)): discard
    newProcTmpl(`E`, `baseE`)
    `addTp`(`typ`, `btyp`)
    `typ`.name = `eeS`

declareSubError Overflow, Arithmetic
declareSubError ZeroDivision, Arithmetic
declareSubError Index, Lookup
declareSubError Key, Lookup
declareSubError UnboundLocal, Name
declareSubError NotImplemented, Runtime

template newAttributeError*(tobj: PyObject, attrName: PyStrObject): untyped =
  let msg = newPyStr(tobj.pyType.name) & newPyAscii" has no attribute " & attrName
  let exc = newAttributeError(msg)
  exc.name = attrName
  exc.obj = tobj
  exc

template newIndexTypeError*(typeName: PyStrObject, obj:PyObject): untyped =
  let name = obj.pyType.name
  let msg = typeName & newPyAscii(" indices must be integers or slices, not ") & newPyStr name
  newTypeError(msg)
