
import std/macros
import ./paramsMeta
import ../../Objects/[
  pyobjectBase,
  exceptions,
]

proc getPyParamConverterImpl*(v: NimNode, isTyped=false): tuple[varname, cvt: NimNode] =
  let cvtPraId = bindSym"convertVia"
  var
    caller = ident"toval"
    varname = v
  if v.kind == nnkPragmaExpr:
    varname = v[0]
    let pragmas = v[1]
    pragmas.expectKind nnkPragma
    for pragma in pragmas:
      if pragma.kind == nnkCall and (
          if isTyped: pragma[0] == cvtPraId
          else: pragma[0].eqIdent cvtPraId.strVal
      ):
        caller = pragma[1]
        break
  (varname, caller)

macro tovalAux*(res: PyObject, v): PyBaseErrorObject =
  let (v, call) = v.getPyParamConverterImpl
  call.newCall(res, v)

proc isKwOnlyStartImpl*(p: NimNode): bool =
  if p.kind != nnkPragmaExpr: return
  let pragmas = p[1]
  assert pragmas.kind == nnkPragma
  let id = bindSym"startKwOnly"
  for p in pragmas:
    if p.eqIdent id:
      return true

proc getNameOfParam*(p: NimNode): NimNode =
  if p.kind == nnkPragmaExpr: p[0]
  else: p

