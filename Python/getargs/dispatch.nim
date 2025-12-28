
import std/macros
import ./[
  tovalUtils,
  va_and_kw,
  tovals,
]
export tovals
import ../../Objects/[
  pyobjectBase,
  dictobject,
  exceptions,
]


proc clinicGenAux*(hasSelf: bool, genedPureNameStr: string, def: NimNode, exported=true): NimNode =
  ## impl for pragma for proc def
  let
    originFuncName = def.name
    pureName = ident genedPureNameStr
    name = if exported: # exported
      pureName.postfix"*"
    else: pureName

  let params = def.params
  var vargs = newNimNode nnkBracket
  var beginKwOnly = false
  var kwOnlyList: seq[string]

  var callOriArgs: seq[NimNode]
  let resType = params[0]
  var start = 1
  if hasSelf: start = 2

  for i in start..<params.len:
    let
      pDef = params[i]
      pName = pDef[0].getNameOfParam
    assert pDef.len == 3, "#TODO:clinic current each param match one type (e.g. `a, b: int` shall be written as `a: int, b: int`)"
    callOriArgs.add pName
    if beginKwOnly:
      kwOnlyList.add pName.strVal
    elif pDef[0].isKwOnlyStartImpl:
      beginKwOnly = true
      kwOnlyList.add pName.strVal
    vargs.add pDef
  let
    nparam_args = ident"args"
    nparam_kwargs = ident"kwargs"
  let parserCall = PyArg_VaParseTupleAndKeywordsAs(newStrLitNode genedPureNameStr, nparam_args, nparam_kwargs, kwOnlyList, vargs)
  let nparams = nnkFormalParams.newTree resType
  let PyObjT = bindSym"PyObject"
  if hasSelf:
    let self = ident"self"
    nparams.add newIdentDefs(self, PyObjT)
    callOriArgs.insert self, 0

  nparams.add newIdentDefs(nparam_args, nnkBracketExpr.newTree(bindSym"openArray", PyObjT))
  nparams.add newIdentDefs(nparam_kwargs, PyObjT)
  let callOrigin = originFuncName.newCall callOriArgs
  let body = quote do:
    let `nparam_kwargs` = PyDictObject `nparam_kwargs`
    retIfExc `parserCall`
    `callOrigin`
  let emptyn = newEmptyNode()
  let nproc = nnkProcDef.newTree(name, emptyn, emptyn,  nparams, nnkPragma.newTree bindSym"pyCFuncPragma", emptyn, body)
  result = newStmtList(def, nproc)

proc clinicGenImplWithPrefix*(prefix: string, def: NimNode): NimNode =
  let
    originFuncName = def.name
    genedPureNameStr = prefix & originFuncName.strVal
    exported = def[0].kind == nnkPostfix
  if exported:
    assert def[0][0].strVal == "*"
  clinicGenAux(false, genedPureNameStr, def, exported)


macro clinicGenWithPrefix*(prefix: static[string], def) =
  clinicGenImplWithPrefix(prefix, def)

macro clinicGen*(name; exported: static[bool], def) =
  ## pragma for proc def.
  ## 
  ## Named after CPython's clinic
  ##
  ## main part of exportnpy, just before registering into module dict
  clinicGenAux(false, name.strVal, def, exported)
macro clinicGenMeth*(name; exported: static[bool], def) =
  clinicGenAux(true, name.strVal, def, exported)

macro bltin_clinicGen*(def) = clinicGenImplWithPrefix("builtin_", def)
