import std/macros
import ./[
  pysig2nim,
]

proc getProcDefFromSpec*(spec: NimNode): NimNode =
  ## .. note:: returns a `nnkProcDef`, whose body may be empty
  let emptyn = newEmptyNode()
  let head = spec[0]
  let procName = head.strVal
  var params = nnkFormalParams.newTree(ident"auto")
  for i in 1..<spec.len:
    let (name, tp, defval) = parseOneParam(spec[i])
    params.add newIdentDefs(name, tp, defval)
  result = nnkProcDef.newTree(
    ident(procName),
    emptyn,
    emptyn,
    params,
    emptyn,
    emptyn,
    emptyn, #newNimNode nnkDiscardStmt,
  )
