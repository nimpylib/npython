
import std/macros
import ./[
  base, utils, basetok,
]
import ../pyobject

var subErrs*{.compileTime.}: seq[string]  ## all subclasses' names of BaseException except Exception
proc declareSubErrorImpl(pyTypeName, errTok: NimNode; baseTypeName: NimNode): NimNode =
  let
    eeS = pyTypeName.strVal
    typ = ident "py" & pyTypeName.strVal & "ObjectType"
    btyp = ident "py" & baseTypeName.strVal & "ObjectType"
  subErrs.add eeS
  result = quote do:
    declarePyType `pyTypeName`(base(`baseTypeName`)): discard
    newProcTmpl(`pyTypeName`, `errTok`)
    `addTp`(`typ`, `btyp`)
    `typ`.name = `eeS`

macro declareSubError(E, baseE) =
  let
    basePyTypeName = ident baseE.strVal & "Error"
    pyTypeName = ident E.strVal & "Error"
  declareSubErrorImpl(pyTypeName, baseE, basePyTypeName)
#macro declareSubBaseException(E) = declareSubErrorImpl(E, ident"BaseException", ident"BaseException")

declareSubError Overflow, Arithmetic
declareSubError ZeroDivision, Arithmetic
declareSubError Index, Lookup
declareSubError Key, Lookup
declareSubError UnboundLocal, Name
declareSubError NotImplemented, Runtime
declareSubError Recursion, Runtime
declareSubError ModuleNotFound, Import


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
