
import std/macros
import ./paramsMeta
import ../../Objects/[
  pyobjectBase,
  exceptions,
]

proc fetchPragmaArg(mayBePragmaExpr, tofind: NimNode, defval: NimNode, argsIsTyped=false): tuple[head: NimNode, val: NimNode] =
  ##[ do following pusedo match code
  ```
  val = defval
  match mayBePragmaExpr
  | head{.tofind(val).}
  | head
  ```
  ]##
  var v = mayBePragmaExpr
  result.val = defval
  if v.kind == nnkPragmaExpr:
    result.head = v[0]
    let pragmas = v[1]
    pragmas.expectKind nnkPragma
    for i, pragma in pragmas:
      if pragma.kind in {nnkCall, nnkCallStrLit} and (
          if argsIsTyped: pragma[0] == tofind
          else: pragma[0].eqIdent tofind.strVal
      ):
        result.val = pragma[1]
        pragmas.del i, 1
        if pragmas.len > 0:
          v[1] = pragmas
        else:
          v = v[0]
        break
  else:
    result.head = v

proc getPyParamConverterImpl*(v: NimNode, isTyped=false): tuple[varname, cvt: NimNode] =
  let res = v.fetchPragmaArg(bindSym"convertVia", ident"toval")
  (res[0], res[1])

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

proc getPyNameOfParamAsStr*(n: NimNode): string =
  ## consider prefer `{.AsPyParam.}`'s argument if present
  if n.kind == nnkAccQuoted:
    n.expectLen 1
    n[0].strVal
  else:
    let tup = n.fetchPragmaArg(bindSym"AsPyParam", nil)
    var pyname = tup.val
    if pyname.isNil:
      pyname = tup.head
    pyname.strVal
