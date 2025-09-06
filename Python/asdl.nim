import macros
import hashes
import sequtils
import strutils


import ../Objects/[pyobject, stringobject]

type
  AstNodeBase* = ref object of RootObj

  Asdlint* = ref object of AstNodeBase
    value*: int

  AsdlIdentifier* = ref object of AstNodeBase
    value*: PyStrObject

  AsdlConstant* = ref object of AstNodeBase
    value*: PyObject

proc pragmaRaiseNode*(p: NimNode = nil, raises: varargs[NimNode]): NimNode =
  nnkPragma.newTree(nnkExprColonExpr.newTree(ident"raises", newNimNode(nnkBracket, p).add(raises)))

proc pragmaRaiseSyntaxErrorNode*(p: NimNode=nil): NimNode = p.pragmaRaiseNode ident"SyntaxError"

method hash*(node: AstNodeBase): Hash {. base, raises: [] .} = 
  when defined(js):
    hashes.hash(cast[pointer](node))
    # NIM-BUG: if cast[int]:
    #  at rt: SyntaxError: Cannot convert [object Object] to a BigInt
  else:
    hash(cast[int](node))


proc genMember(member: NimNode): NimNode = 
  case member.kind
  of nnkCommand: # int x, etc
    result = newIdentDefs(postFix(member[1], "*"), ident("Asdl" & $member[0]))
  of nnkInfix: # expr* a, etc
    let op = member[0]
    expectKind(op, nnkIdent)
    if op.strval == "*":
      result = newIdentDefs(
                 postFix(member[2], "*"),
                 nnkBracketExpr.newTree(
                   ident("seq"),
                   ident("Asdl" & $member[1])
                 )
               )
    else: # don't mind `?`
      result = newIdentDefs(postFix(member[2], "*"), ident("Asdl" & $member[1]))
  else:
    assert false

# name of the type
proc getDefName(def: NimNode): string = 
  expectKind(def, {nnkCall, nnkIdent})
  case def.kind
  of nnkCall:
    result = $def[0]
  of nnkIdent:
    result = $def
  else:
    assert false

proc genType(def: NimNode, prefix: string, parent: string): NimNode = 
  # with () or not
  expectKind(def, {nnkCall, nnkIdent})
  # the list of members
  let recList = nnkRecList.newTree()
  if def.kind == nnkCall:
    for i in 1..<def.len:
      recList.add(genMember(def[i]))
  if parent == "AstNodeBase":
    let tkName = "Asdl" & getDefName(def) & "Tk"
    recList.add(newIdentDefs(postFix(ident("kind"), "*"), ident(tkName)))

  result = nnkTypeDef.newTree(
    nnkPostFix.newTree(
      ident("*"),
      ident(prefix & getDefName(def)),
    ),
    newEmptyNode(),
    nnkRefTy.newTree(
      nnkObjectTy.newTree(
        newEmptyNode(),
        nnkOfInherit.newTree(ident(parent)),
        recList
      )
    )
  )

proc genAsdlToken(subtypes: NimNode, parentName: string): NimNode = 
  
  # asdl type token
  let enumList = nnkEnumTy.newTree(newEmptyNode())
  for subType in subtypes:
    let name = getDefName(subType)
    enumlist.add(ident(name))
  result = nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nnkPragmaExpr.newTree(
        postFix(
          ident(parentName & "Tk"),
          "*"
        ),
        nnkPragma.newTree(
          newIdentNode("pure")
        )
      ),
      newEmptyNode(),
      enumList
    )
  )


template newFuncTmpl(typeName, parentName) = 
  proc `newAst typeName`*: `Ast typeName` = 
    new result
    result.kind = `parentName Tk`.`typeName`


proc genTypeNewFunc(subType: NimNode, parentName: string): NimNode = 
  let typeName = getDefName(subType)
  getAst(newFuncTmpl(ident(typeName), ident(parentName)))


method `$`*(node: AstNodeBase): string {.base, raises: [].} = 
  # we don't want to stop here by raising errors or so
  # because printing a full tree might be helpful
  "!!!DUMMY!!!"

method `$`*(node: AsdlInt): string {.raises: [].} = 
  $node.value

method `$`*(node: AsdlIdentifier): string {.raises:[].} = 
  $node.value

method `$`*(node: AsdlConstant): string {.raises:[].} = 
  $node.value

const tab = "   "

proc indent(str: string, level=1): seq[string] = 
  var indent = ""
  for i in 0..<level:
    indent &= tab
  split(str, "\n").mapIt(indent & it)


proc addToSeq(elemNode: NimNode, indentLevel=1): NimNode = 
  # if elemNode == nil: add "Nil Node"
  # else add $elemNode

  result = nnkIfStmt.newTree(
    nnkElifBranch.newTree(
      nnkInfix.newTree(
        ident("=="),
        elemNode,
        newNilLit()
      ),
      nnkStmtList.newTree(
        nnkCall.newTree(
          nnkDotExpr.newTree(
            ident("stringSeq"),
            ident("add")
          ),
          nnkCall.newTree(
            ident("indent"),
            newStrLitNode("Nil Node"),
            newIntLitNode(indentLevel)
          )
        )
      )
    ),
    nnkElse.newTree(
      nnkCall.newTree(
        nnkDotExpr.newTree(
          ident("stringSeq"),
          ident("add")
        ),
        nnkCall.newTree(
          ident("indent"),
          nnkPrefix.newTree(
            ident("$"),
            elemNode
          ),
          newIntLitNode(indentLevel)
        )
      )
    )
  )



proc genMemberRepr(member: NimNode): NimNode = 
  result = newStmtList()
  if member.kind == nnkCommand or 
      (member.kind == nnkInfix and member[0].strVal == "?"):
    result.add(
      addToSeq(
        nnkDotExpr.newTree(
          ident("node"),
          member[^1]
        )
      )
    )
  else:
    result.add(
      nnkCall.newTree(
        nnkDotExpr.newTree(
          ident("stringSeq"),
          ident("add")
        ),
        nnkInfix.newTree(
          ident("&"),
          ident("tab"),
          newStrLitNode($member[2])
        )
      )
    )
    result.add(
      nnkForStmt.newTree(
        ident("child"),
        nnkDotExpr.newTree(
          ident("node"),
          member[2]
        ),
        nnkStmtList.newTree(
          addToSeq(ident("child"), 2)
        )
      )
    )


proc methodDeclare(prefix, name: string): NimNode = 
  result = nnkMethodDef.newTree(
    nnkPostFix.newTree(
      ident("*"),
      nnkAccQuoted.newTree(ident("$")),
    ),
    newEmptyNode(),
    newEmptyNode(),
    nnkFormalParams.newTree(
      ident("string"),
      newIdentDefs(ident("node"), ident(prefix & name))
    ),
    pragmaRaiseNode(),
    newEmptyNode(),
    newEmptyNode()
  )

proc genReprMethod(def: NimNode, prefix: string): NimNode = 
  let name = getDefName(def)
  var code = newStmtList() 
  case def.kind
  of nnkCall:
    code.add(
      nnkVarSection.newTree(
        nnkIdentDefs.newTree(
          ident("stringSeq"),
          newEmptyNode(),
          nnkPrefix.newTree(
            ident("@"),
            nnkBracket.newTree(
              newStrLitNode(name)
            )
          )
        )
      )
    )
    for i in 1..<def.len:
      code.add(genMemberRepr(def[i]))
    code.add(
      nnkreturnstmt.newtree(
        parsestmt("""stringseq.join("\n")"""))
      )
  of nnkIdent:
    code.add(
      nnkReturnStmt.newTree(
        newStrLitNode(name)
      )
    )
  else:
    assert false
  var methodAst = methodDeclare(prefix, name)
  methodAst[^1] = code
  result = methodAst

macro genAsdlTypes(inputTree: untyped): untyped = 
  result = newStmtList()
  # asdl tokens
  for child in inputTree:
    let parentName = "Asdl" & getDefName(child[0])
    let right = child[1]
    expectKind(right, {nnkPar, nnkTupleConstr})
    # generate asdl tokens
    result.add(genAsdlToken(right, parentName))

  # asdl types
  var baseTypes = nnkTypeSection.newTree
  for child in inputTree:
    expectKind(child, nnkAsgn)
    let left = child[0]
    baseTypes.add(genType(left, "Asdl", "AstNodeBase"))
  result.add(baseTypes)

  # ast types
  for child in inputTree:
    let parentName = "Asdl" & getDefName(child[0])
    let right = child[1]
    expectKind(right, {nnkPar, nnkTupleConstr})
    # generate ast types
    for subType in right:
      result.add(
        nnkTypeSection.newTree(
          genType(subType, "Ast", parentName)
        ) 
      )
      result.add(genTypeNewFunc(subType, parentName))

  # forward declarations
  for child in inputTree:
    result.add(methodDeclare("Asdl", getDefName(child[0])))
    for subType in child[1]:
      result.add(methodDeclare("Ast", getDefName(subType)))

  # implementations
  for child in inputTree:
    result.add(genReprMethod(child[0], "Asdl"))
    for subType in child[1]:
      result.add(genReprMethod(subType, "Ast"))


# things like stmt* body are recognized as stmt * body and
# a warning about spacing will be issued
# nimpretty doesn't like this idea. So don't format this file
{.warning[Spacing]: off.} 

genAsdlTypes:

  modl = (
    Module(stmt* body), 
    Interactive(stmt* body),
    Expression(expr body), 
    Suite(stmt* body), 
  )

  # XXX Jython will be different
  # col_offset is the byte offset in the utf8 string the parser uses
  stmt(int lineno, int col_offset) = (
    FunctionDef(
      identifier name, arguments args,
      stmt* body, expr* decorator_list, expr? returns
    ),
    AsyncFunctionDef(
      identifier name, arguments args,
      stmt* body, expr* decorator_list, expr? returns
    ),

    ClassDef(identifier name, expr* bases, keyword* keywords,
             stmt* body, expr* decorator_list),
    Return(expr? value),

    Delete(expr* targets),
    Assign(expr* targets, expr value),
    AugAssign(expr target, operator op, expr value), # augmented asgn (in-place op)
    # 'simple' indicates that we annotate simple name without parens
    AnnAssign(expr target, expr annotation, expr? value, int simple),

    # use 'orelse' because else is a keyword in target languages
    For(expr target, expr iter, stmt* body, stmt* orelse),
    AsyncFor(expr target, expr iter, stmt* body, stmt* orelse),
    While(expr test, stmt* body, stmt* orelse),
    If(expr test, stmt* body, stmt* orelse),
    With(withitem* items, stmt* body),
    AsyncWith(withitem* items, stmt* body),

    Raise(expr? exc, expr? cause),
    Try(stmt* body, excepthandler* handlers, stmt* orelse, stmt* finalbody),
    Assert(expr test, expr? msg),

    Import(alias* names),
    ImportFrom(identifier? module, alias* names, int? level),

    Global(identifier* names),
    Nonlocal(identifier* names),
    Expr(expr value),
    Pass,
    Break,
    Continue,
  )

  # col_offset is the byte offset in the utf8 string the parser uses
  expr(int lineno, int col_offset) = (
    # BoolOp() can use left & right?
    BoolOp(boolop op, expr* values),
    BinOp(expr left, operator op, expr right),
    UnaryOp(unaryop op, expr operand),
    Lambda(arguments args, expr body),
    IfExp(expr test, expr body, expr orelse),
    Dict(expr* keys, expr* values),
    Set(expr* elts),
    ListComp(expr elt, comprehension* generators),
    SetComp(expr elt, comprehension* generators),
    DictComp(expr key, expr value, comprehension* generators),
    GeneratorExp(expr elt, comprehension* generators),
    # the grammar constrains where yield expressions can occur
    Await(expr value),
    Yield(expr? value),
    YieldFrom(expr value),
    # need sequences for compare to distinguish between
    # x < 4 < 3 and (x < 4), < 3
    Compare(expr left, cmpop* ops, expr* comparators),
    Call(expr fun, expr* args, keyword* keywords),
    FormattedValue(expr value, int? conversion, expr? format_spec),
    JoinedStr(expr* values),
    Constant(constant value),

    # the following expression can appear in assignment context
    Attribute(expr value, identifier attr, expr_context ctx),
    Subscript(expr value, slice slice, expr_context ctx),
    Starred(expr value, expr_context ctx),
    Name(identifier id, expr_context ctx),
    List(expr* elts, expr_context ctx),
    Tuple(expr* elts, expr_context ctx),
  )

  expr_context = (Load, Store, Del, AugLoad, AugStore, Param)

  slice = (
    Slice(expr? lower, expr? upper, expr? step),
    ExtSlice(slice* dims),
    Index(expr value)
  )

  boolop = (And, Or)

  operator = (Add, Sub, Mult, MatMult, Div, Mod, Pow, LShift,
    RShift, BitOr, BitXor, BitAnd, FloorDiv)

  unaryop = (Invert, Not, UAdd, USub)

  cmpop = (Eq, NotEq, Lt, LtE, Gt, GtE, Is, IsNot, In, NotIn)

  comprehension = (Comprehension(expr target, expr iter, expr* ifs, int is_async))

  excepthandler(int lineno, int col_offset) = 
    (ExceptHandler(expr? type, identifier? name, stmt* body))

  arguments = (Arguments(arg* args, arg? vararg, arg* kwonlyargs, 
                expr* kw_defaults, arg? kwarg, expr* defaults))

  arg(int lineno, int col_offset) = (Arg(identifier arg, expr? annotation))

  # keyword arguments supplied to call (NULL identifier for **kwargs)
  keyword = (Keyword(identifier? arg, expr value))

  # import name with optional 'as' alias.
  alias = (Alias(identifier name, identifier? asname))

  withitem = (Withitem(expr context_expr, expr? optional_vars))

{.warning[Spacing]: on.}


when isMainModule:
  let t = newAstWithitem()
  echo t.kind
