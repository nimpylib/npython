
import std/macros
import ./[
  base, utils,
]
import ../pyobject

var subErrs*{.compileTime.}: seq[string]  ## all subclasses' names of BaseException except Exception
proc declareSubErrorImpl(E, baseE: NimNode; pyTypeName = ident baseE.strVal & "Error"): NimNode =
  let
    eeS = E.strVal & "Error"
    ee = ident eeS
    typ = ident "py" & ee.strVal & "ObjectType"
    btyp = ident "py" & pyTypeName.strVal & "ObjectType"
  subErrs.add eeS
  result = quote do:
    declarePyType `ee`(base(`pyTypeName`)): discard
    newProcTmpl(`E`, `baseE`)
    `addTp`(`typ`, `btyp`)
    `typ`.name = `eeS`

macro declareSubError(E, baseE) = declareSubErrorImpl(E, baseE)

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
