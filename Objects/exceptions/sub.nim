
import std/macros
import ./[
  base, utils, basetok,
]
import ../pyobject

var subErrs*{.compileTime.}: seq[string]  ## all subclasses' (including subsub, etc) names of BaseException except Exception
proc declareSubErrorImplAux(pyTypeName: NimNode; baseTypeName: NimNode;
    fields: NimNode): NimNode =
  let
    eeS = pyTypeName.strVal
    typ = ident "py" & pyTypeName.strVal & "ObjectType"
    btyp = ident "py" & baseTypeName.strVal & "ObjectType"
  subErrs.add eeS
  result = quote do:
    declarePyType(`pyTypeName`(base(`baseTypeName`)), `fields`)
    `addTp`(`typ`, `btyp`)
    `typ`.name = `eeS`

proc declareSubErrorImpl(pyTypeName, errTok: NimNode; baseTypeName: NimNode; fields: NimNode): NimNode =
  result = declareSubErrorImplAux(pyTypeName, baseTypeName, fields)
  result.add quote do:
    newProcTmpl(`pyTypeName`, `errTok`)

template prepare{.dirty.} =
  let
    basePyTypeName = ident baseE.strVal & "Error"
    pyTypeName = ident E.strVal & "Error"
macro declareSubError(E, baseE; fields) =
  prepare
  declareSubErrorImpl(pyTypeName, baseE, basePyTypeName, fields)

macro declareSubSubError(E, baseE; fields) =
  prepare
  declareSubErrorImplAux(pyTypeName, basePyTypeName, fields)
template declareSubError(E, baseE) = declareSubError(E, baseE): discard
template declareSubSubError(E, baseE) = declareSubSubError(E, baseE): discard

#macro declareSubBaseException(E) = declareSubErrorImpl(E, ident"BaseException", ident"BaseException")

declareSubError Overflow, Arithmetic
declareSubError ZeroDivision, Arithmetic
declareSubError FloatingPoint, Arithmetic
declareSubError Index, Lookup
declareSubError Key, Lookup
declareSubError UnboundLocal, Name
declareSubError NotImplemented, Runtime
declareSubError Recursion, Runtime
declareSubError PythonFinalization, Runtime
declareSubError ModuleNotFound, Import
declareSubError IO, OS
declareSubError Connect, OS

declareSubSubError Unicode, Value:
  encoding{.member.}: PyObject
  obj{.member"member".}: PyObject
  start{.member.}: int
  stop{.member"end".}: int
  reason{.member.}: PyObject

declareSubSubError UnicodeDecode, Unicode
declareSubSubError UnicodeEncode, Unicode
declareSubSubError UnicodeTranslate, Unicode

declareSubSubError Indentation, Syntax
declareSubSubError Tab, Indentation

template subos(exc){.dirty.} =
  declareSubSubError exc, OS

subos BlockingIO
subos ChildProcess
subos Connection
subos FileExists
subos FileNotFound
subos Interrupted
subos IsADirectory
subos NotADirectory
subos Permission
subos ProcessLookup
subos Timeout

template subcon(exc){.dirty.} =
  declareSubSubError exc, Connect

subcon BrokenPipe
subcon ConnectionAborted
subcon ConnectionRefused
subcon ConnectionReset

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
