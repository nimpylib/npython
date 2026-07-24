
import std/macros

proc baseIdName(idDef: NimNode): string =
  var id = idDef
  if id.kind == nnkPostfix:  # export
    id = id[1]
  id.strVal

iterator fieldNamesForDef(tDef: NimNode): string =
  tDef.expectKind nnkTypeDef
  var objTy = tDef[2]
  if objTy.kind == nnkRefTy:
    objTy = objTy[0]
  let fields = objTy[2]

  for idDef in fields:
    for i in 0..<idDef.len-2:
      yield idDef[i].baseIdName
iterator fieldNames(T: NimNode): string =
  let tDef = T.getImpl
  for field in tDef.fieldNamesForDef():
    yield field


macro forFields*(loopVar, loopVarForId; T: typedesc; body) =
  result = newStmtList()
  let forFieldsCb = genSym(nskTemplate, "forFieldsCb")
  result.add quote do:
    template `forFieldsCb`(`loopVar`, `loopVarForId`) =
      `body`
  for field in T.fieldNames():
    result.add newCall(forFieldsCb, newLit field, ident field)
  result = newBlockStmt(result)

macro fieldNameArrayAdded*(T: typedesc; added: typed): untyped #[array[N, string]]# =
  result = newNimNode nnkBracket
  for field in T.fieldNames():
    result.add newLit field
  result.add added

macro initFromLocals*(T: typedesc): untyped =
  let tDef = T.getImpl
  result = nnkObjConstr.newTree ident tDef[0].baseIdName
  for field in tDef.fieldNamesForDef():
    let id = ident field
    result.add nnkExprColonExpr.newTree(id, id)

when isMainModule:
  type X = ref object
    a*: int
    b: string
  #m Slice
  forFields(f, fId, X):
    echo f, ' ', astToStr(fId)
  var
    a = 1
    b = "asd"
  echo repr initFromLocals(X)

