
import std/macros

proc parseOneParam*(child: NimNode): tuple[name, tp, defval: NimNode] =
  var name: NimNode
  var tp: NimNode = newEmptyNode()
  var defval: NimNode = newEmptyNode()
  name = child[0]
  case child.kind
  of nnkExprColonExpr:
    tp = child[1]
  of nnkExprEqExpr:
    #TODO: handle startPosOnly, startKwOnly
    defval = child[1]

    let argl = name
    var paramColTyp: NimNode

    # handle `(a: int) = 1`
    #   (as `a: int = 1` is invalid Nim syntax if within a `nkCall` or `nkObjConstr`)
    if argl.kind == nnkTupleConstr and argl.len == 1 and (
      paramColTyp = argl[0]; paramColTyp.kind == nnkExprColonExpr
    ):
      name = paramColTyp[0]
      tp = paramColTyp[1]
  of nnkIdentDefs:
    # when used by getargs/dispatch (clinicGenMethod)
    assert child.len == 3, "params notation like a, b: int is not allowed, please write as a: int, b: int"
    tp = child[1]
    if child[2].kind != nnkEmpty:
      defval = child[2]
  else:
    error "invalid arg type definition", child

  (name, tp, defval)
