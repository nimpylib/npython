import macros
import tables

import strutils
import typetraits
import strformat

import asdl
import ../Parser/[token, parser]
import ../Objects/[pyobject, noneobject,
  numobjects, boolobjectImpl, stringobjectImpl,
  sliceobject  # pyEllipsis
  ]
import ../Utils/[utils, compat]


template raiseSyntaxError*(msg: string, astNode: untyped) = 
  raiseSyntaxError(msg, "", astNode.lineNo.value, astNode.colOffset.value)

template raiseSyntaxError(msg: string, parseNode: ParseNode) = 
  raiseSyntaxError(msg, "", parseNode.tokenNode.lineNo, parseNode.tokenNode.colNo)

template raiseSyntaxError(msg: string) = 
  raiseSyntaxError(msg, parseNode)

# in principle only define constructor for ast node that 
# appears more than once. There are exceptions below,
# but it should be keeped since now.

proc newAstExpr(expr: AsdlExpr): AstExpr = 
  result = newAstExpr()
  result.value = expr


proc newInt(value: int): AsdlInt = 
  new result
  result.value = value


proc newIdentifier*(value: string): AsdlIdentifier = 
  new result
  result.value = newPyString(value)


proc newAstName(tokenNode: TokenNode): AstName = 
  assert tokenNode.token in contentTokenSet
  result = newAstName()
  result.id = newIdentifier(tokenNode.content)
  # start in load because it's most common, 
  # then we only need to take care of store (such as lhs of `=`)
  result.ctx = newAstLoad()

proc newAstConstant(obj: PyObject): AstConstant = 
  result = newAstConstant()
  result.value = new AsdlConstant 
  result.value.value = obj

proc newBoolOp(op: AsdlBoolop, values: seq[AsdlExpr]): AstBoolOp =
  result = newAstBoolOp()
  result.op = op
  result.values = values

proc newBinOp(left: AsdlExpr, op: AsdlOperator, right: AsdlExpr): AstBinOp =
  result = newAstBinOp()
  result.left = left
  result.op = op
  result.right = right

proc newUnaryOp(op: AsdlUnaryop, operand: AsdlExpr): AstUnaryOp = 
  result = newAstUnaryOp()
  result.op = op
  result.operand = operand


proc newList(elts: seq[AsdlExpr]): AstList = 
  result = newAstList()
  result.elts = elts
  result.ctx = newAstLoad()

proc newTuple(elts: seq[AsdlExpr]): AstTuple = 
  result = newAstTuple()
  result.elts = elts
  result.ctx = newAstLoad()

template setNo(astNode: untyped, parseNode: ParseNode) = 
  astNode.lineNo = newInt(parseNode.tokenNode.lineNo)
  astNode.colOffset = newInt(parseNode.tokenNode.colNo)

template copyNo(astNode1, astNode2: untyped) = 
  astNode1.lineNo = astNode2.lineNo
  astNode1.colOffset = astNode2.colOffset

proc astDecorated(parseNode: ParseNode): AsdlStmt
proc astFuncdef(parseNode: ParseNode): AstFunctionDef
proc astParameters(parseNode: ParseNode): AstArguments
proc astTypedArgsList(parseNode: ParseNode): AstArguments
proc astTfpdef(parseNode: ParseNode): AstArg

proc astStmt(parseNode: ParseNode): seq[AsdlStmt]
proc astSimpleStmt(parseNode: ParseNode): seq[AsdlStmt] 
proc astSmallStmt(parseNode: ParseNode): AsdlStmt
proc astExprStmt(parseNode: ParseNode): AsdlStmt
proc astTestlistStarExpr(parseNode: ParseNode): AsdlExpr
proc astAugAssign(parseNode: ParseNode): AsdlOperator

proc astDelStmt(parseNode: ParseNode): AsdlStmt
proc astPassStmt(parseNode: ParseNode): AstPass
proc astFlowStmt(parseNode: ParseNode): AsdlStmt
proc astBreakStmt(parseNode: ParseNode): AsdlStmt
proc astContinueStmt(parseNode: ParseNode): AsdlStmt
proc astReturnStmt(parseNode: ParseNode): AsdlStmt
proc astYieldStmt(parseNode: ParseNode): AsdlStmt
proc astRaiseStmt(parseNode: ParseNode): AstRaise

proc astImportStmt(parseNode: ParseNode): AsdlStmt
proc astImportName(parseNode: ParseNode): AsdlStmt
proc astDottedAsNames(parseNode: ParseNode): seq[AstAlias]
proc astDottedName(parseNode: ParseNode): AstAlias
proc astGlobalStmt(parseNode: ParseNode): AsdlStmt
proc astNonlocalStmt(parseNode: ParseNode): AsdlStmt
proc astAssertStmt(parseNode: ParseNode): AstAssert

proc astCompoundStmt(parseNode: ParseNode): AsdlStmt
proc astAsyncStmt(parseNode: ParseNode): AsdlStmt
proc astIfStmt(parseNode: ParseNode): AstIf
proc astWhileStmt(parseNode: ParseNode): AstWhile
proc astForStmt(parseNode: ParseNode): AsdlStmt
proc astTryStmt(parseNode: ParseNode): AstTry
proc astExceptClause(parseNode: ParseNode): AstExceptHandler
proc astWithStmt(parseNode: ParseNode): AsdlStmt
proc astSuite(parseNode: ParseNode): seq[AsdlStmt]

proc astTest(parseNode: ParseNode): AsdlExpr
proc astOrTest(parseNode: ParseNode): AsdlExpr
proc astAndTest(parseNode: ParseNode): AsdlExpr
proc astNotTest(parseNode: ParseNode): AsdlExpr
proc astComparison(parseNode: ParseNode): AsdlExpr
proc astCompOp(parseNode: ParseNode): AsdlCmpop

proc astExpr(parseNode: ParseNode): AsdlExpr
proc astXorExpr(parseNode: ParseNode): AsdlExpr
proc astAndExpr(parseNode: ParseNode): AsdlExpr
proc astShiftExpr(parseNode: ParseNode): AsdlExpr
proc astArithExpr(parseNode: ParseNode): AsdlExpr
proc astTerm(parseNode: ParseNode): AsdlExpr
proc astFactor(parseNode: ParseNode): AsdlExpr
proc astPower(parseNode: ParseNode): AsdlExpr
proc astAtomExpr(parseNode: ParseNode): AsdlExpr
proc astAtom(parseNode: ParseNode): AsdlExpr
proc astTestlistComp(parseNode: ParseNode): seq[AsdlExpr]
proc astTrailer(parseNode: ParseNode, leftExpr: AsdlExpr): AsdlExpr
proc astSubscriptlist(parseNode: ParseNode): AsdlSlice
proc astSubscript(parseNode: ParseNode): AsdlSlice
proc astExprList(parseNode: ParseNode): seq[AsdlExpr]
proc astTestList(parseNode: ParseNode): AsdlExpr
proc astDictOrSetMaker(parseNode: ParseNode): AsdlExpr
proc astClassDef(parseNode: ParseNode): AstClassDef
proc astArglist(parseNode: ParseNode, callNode: AstCall): AstCall
proc astArgument(parseNode: ParseNode): AsdlExpr
proc astSyncCompFor(parseNode: ParseNode): seq[AsdlComprehension]
proc astCompFor(parseNode: ParseNode): seq[AsdlComprehension]


# DSL to simplify function definition
# should use a pragma instead?
proc genParamsSeq(paramSeq: NimNode): seq[NimNode] = 
  expectKind(paramSeq, nnkBracket)
  assert 0 < paramSeq.len
  result.add(paramSeq[0])
  result.add(newIdentDefs(ident("parseNode"), ident("ParseNode")))
  for i in 1..<paramSeq.len:
    let child = paramSeq[i] # seems NimNode doesn't support slicing
    expectKind(child, nnkExprColonExpr)
    assert child.len == 2
    result.add(newIdentDefs(child[0], child[1]))


proc genFuncDef(tokenIdent: NimNode, funcDef: NimNode): NimNode = 
  # add assert type check for the function
  expectKind(funcDef, nnkStmtList)
  let assertType = nnkCommand.newTree(
    ident("assert"),
    nnkInfix.newTree(
      ident("=="),
      nnkDotExpr.newTree(
        nnkDotExpr.newTree(
          ident("parseNode"),
          ident("tokenNode"),
        ),
        ident("token")
      ),
      nnkDotExpr.newTree(
        ident("Token"),
        tokenIdent
      )
    )
  )

  result = newStmtList(assertType, funcDef)


macro ast(tokenName, paramSeq, funcDef: untyped): untyped = 
  result = newProc(
    ident(fmt"ast_{tokenName}"), 
    genParamsSeq(paramSeq), 
    genFuncDef(tokenName, funcDef)
  )



#  build ast Node according to tokens of children
macro childAst(child, astNode: untyped, tokens: varargs[Token]): untyped = 
  result = nnkCaseStmt.newTree
  # the case condition `child.tokenNode.token`
  result.add(
    newDotExpr(
      newDotExpr(child, ident("tokenNode")),
      ident("token")
      )
  )
  # enter build AST node branch according to token
  for token in tokens:
    result.add(
      nnkOfBranch.newTree(
        newDotExpr(ident("Token"), token),
        newStmtList(
          newAssignment(
            astNode,
            newCall("ast" & $token, child)
          )
        )
      )
    )

  # the else `assert false`
  result.add(
    nnkElse.newTree(
      newStmtList(
        nnkCommand.newTree(
          ident("assert"),
          ident("false")
        )
      )
    )
  )
    
# set context to store. The contexts are load by default
method setStore(astNode: AstNodeBase) {.base.} = 
  if not (astNode of AsdlExpr):
    unreachable
  raiseSyntaxError("can't assign", AsdlExpr(astNode))

method setStore(astNode: AstName) = 
  astnode.ctx = newAstStore()

method setStore(astNode: AstAttribute) = 
  astnode.ctx = newAstStore()

method setStore(astNode: AstSubscript) = 
  astnode.ctx = newAstStore()

method setStore(astNode: AstTuple) = 
  astNode.ctx = newAstStore()
  for elm in astNode.elts:
    elm.setStore()

method setDelete(astNode: AstNodeBase) {.base.} =
  if not (astNode of AsdlExpr):
    unreachable
  raiseSyntaxError("can't delete", AsdlExpr(astNode))
method setDelete(astNode: AstSubscript) =
  astnode.ctx = newAstDel()
method setDelete(astNode: AstAttribute) =
  astnode.ctx = newAstDel()
method setDelete(astNode: AstName) =
  astnode.ctx = newAstDel()

# single_input: NEWLINE | simple_stmt | compound_stmt NEWLINE
ast single_input, [AstInteractive]:
  result = newAstInteractive()
  let child = parseNode.children[0]
  case parseNode.children.len
  of 1:
    case child.tokenNode.token
    of Token.NEWLINE:
      discard
    of Token.simple_stmt:
      result.body = astSimpleStmt(child)
    else:
      unreachable
  of 2:
    result.body.add astCompoundStmt(child)
  else:
    unreachable
  
# file_input: (NEWLINE | stmt)* ENDMARKER
ast file_input, [AstModule]:
  result = newAstModule()
  for child in parseNode.children:
    if child.tokenNode.token == Token.stmt:
      result.body.addCompat astStmt(child)

#[
ast eval_input, []:
  discard
  
]#

# decorator: '@' dotted_name [ '(' [arglist] ')' ] NEWLINE
ast decorator, [AsdlExpr]:
  let dotted_name = parseNode.children[1]
  case dotted_name.children.len
  of 1:
    let name = dottedName.children[0]
    result = newAstName(name.tokenNode)
    setNo(result, name)
  else:
    raiseSyntaxError("dotted name in decorators not implemented", dottedName)

  case parseNode.children.len
  of 3:
    discard
  else:
    var callNode = newAstCall()
    callNode.fun = result
    setNo(callNode, dotted_name.children[0])
    case parseNode.children.len
    of 5:
      result = callNode 
    of 6:
      result = astArglist(parseNode.children[3], callNode)
    else:
      unreachable
  
# decorators: decorator+
ast decorators, [seq[AsdlExpr]]:
  for child in parseNode.children:
    result.add astDecorator(child)
  
# decorated: decorators (classdef | funcdef | async_funcdef)
ast decorated, [AsdlStmt]:
  let decorators = astDecorators(parseNode.children[0])
  let child2 = parseNode.children[1]
  case child2.tokenNode.token
  of Token.classdef:
    let classDef = astClassDef(child2)
    classDef.decorator_list = decorators
    return classDef
  of Token.funcdef:
    let funcDef = astFuncdef(child2)
    funcDef.decorator_list = decorators
    return funcDef
  of Token.async_funcdef:
    raiseSyntaxError("async function not implemented", child2)
  else:
    unreachable

  
ast async_funcdef, [AsdlStmt]:
  raiseSyntaxError("async function definition not implemented", parseNode)
  
# funcdef  'def' NAME parameters ['->' test] ':' suite
ast funcdef, [AstFunctionDef]:
  result = newAstFunctionDef()
  setNo(result, parseNode.children[0])
  result.name = newIdentifier(parseNode.children[1].tokenNode.content)
  result.args = astParameters(parseNode.children[2])
  if not (parseNode.children.len == 5): 
    raiseSyntaxError("Return type annotation not implemented", parseNode)
  result.body = astSuite(parseNode.children[^1])
  assert result != nil

# parameters  '(' [typedargslist] ')'
ast parameters, [AstArguments]:
  case parseNode.children.len
  of 2:
    result = newAstArguments()
  of 3:
    result = astTypedArgsList(parseNode.children[1])
  else:
    unreachable
  

#  typedargslist: (tfpdef ['=' test] (',' tfpdef ['=' test])* [',' [
#        '*' [tfpdef] (',' tfpdef ['=' test])* [',' ['**' tfpdef [',']]]
#      | '**' tfpdef [',']]]
#  | '*' [tfpdef] (',' tfpdef ['=' test])* [',' ['**' tfpdef [',']]]
#  | '**' tfpdef [','])
# 
# Just one tfpdef should be easy enough
ast typedargslist, [AstArguments]:
  result = newAstArguments()
  for i in 0..<parseNode.children.len:
    let child = parseNode.children[i]
    if i mod 2 == 1:
      if not (child.tokenNode.token == Token.Comma):
        raiseSyntaxError("Only support simple function arguments like foo(a,b)", child)
    else:
      if not (child.tokenNode.token == Token.tfpdef):
        raiseSyntaxError("Only support simple function arguments like foo(a,b)", child)
      result.args.add(astTfpdef(child))
  
# tfpdef  NAME [':' test]
ast tfpdef, [AstArg]:
  result = newAstArg()
  result.arg = newIdentifier(parseNode.children[0].tokenNode.content)
  setNo(result, parseNode.children[0])
  
#[
ast varargslist:
  discard
  
ast vfpdef:
  discard
]#
  

# stmt  simple_stmt | compound_stmt
# simply return the child
ast stmt, [seq[AsdlStmt]]:
  let child = parseNode.children[0]
  case child.tokenNode.token
  of Token.simple_stmt:
    result = astSimpleStmt(child)
  of Token.compound_stmt:
    result.add(astCompoundStmt(child))
  else:
    unreachable
  assert 0 < result.len
  for child in result:
    assert child != nil
  
  
# simple_stmt: small_stmt (';' small_stmt)* [';'] NEWLINE
ast simple_stmt, [seq[AsdlStmt]]:
  for child in parseNode.children:
    if child.tokenNode.token == Token.small_stmt:
      result.add(ast_small_stmt(child))
  assert 0 < result.len
  for child in result:
    assert child != nil
  
# small_stmt: (expr_stmt | del_stmt | pass_stmt | flow_stmt |
#              import_stmt | global_stmt | nonlocal_stmt | assert_stmt)
ast small_stmt, [AsdlStmt]:
  let child = parseNode.children[0]
  childAst(child, result, 
    expr_stmt,
    del_stmt,
    pass_stmt,
    flow_stmt,
    import_stmt,
    global_stmt,
    nonlocal_stmt,
    assert_stmt)
  assert result != nil
  
# expr_stmt: testlist_star_expr (annassign | augassign (yield_expr|testlist) |
#                      ('=' (yield_expr|testlist_star_expr))*)
ast expr_stmt, [AsdlStmt]:
  let testlistStarExpr1 = astTestlistStarExpr(parseNode.children[0])
  if parseNode.children.len == 1:
    return newAstExpr(testlistStarExpr1)
  
  let middleChild = parseNode.children[1]
  case middleChild.tokenNode.token
  of Token.Equal: # simple cases like `x=1`
    if not (parseNode.children.len == 3):
      raiseSyntaxError("Only support simple assign like x=1", middleChild)
    let testlistStarExpr2 = astTestlistStarExpr(parseNode.children[2])
    let node = newAstAssign()
    setNo(node, middleChild)
    testlistStarExpr1.setStore
    node.targets.add(testlistStarExpr1) 
    if not (node.targets.len == 1):
      raiseSyntaxError("Assign to multiple target not supported", parseNode)
    node.value = testlistStarExpr2
    result = node
  of Token.augassign: # `x += 1` like
    let testlistStarExpr2 = astTestlist(parseNode.children[2])
    let node = newAstAugAssign()
    setNo(node, middleChild.children[0])
    node.target = testlistStarExpr1
    node.op = astAugAssign(middleChild)
    node.value = testlistStarExpr2
    result = node
  else:
    raiseSyntaxError("Only support simple assignment like a=1", middleChild)
  assert result != nil

  
#ast annassign:
#  discard
  
# testlist_star_expr  (test|star_expr) (',' (test|star_expr))* [',']
ast testlist_star_expr, [AsdlExpr]:
  var elms: seq[AsdlExpr]
  for i in 0..<((parseNode.children.len + 1) div 2):
    let child = parseNode.children[2 * i]
    if not (child.tokenNode.token == Token.test):
      raiseSyntaxError("Star expression not implemented", child)
    elms.add astTest(child)
  if parseNode.children.len == 1:
    result = elms[0]
  else:
    result = newTuple(elms)
  copyNo(result, elms[0])
  assert result != nil


#[
  var op: AsdlAugAssign
  case token
  of Token.Plusequal:
    op = newAstPlusequal()
  of Token.Minequal:
    op = newAstMinequal()
  else:
    unreachable
  var nodeSeq = @[firstAstNode]
  for idx in 1..parseNode.children.len div 2:
    let nextChild = parseNode.children[2 * idx]
    let nextAstNode = childAstFunc(nextChild)
    nodeSeq.add(nextAstNode)
  result = newAugAssign(op, nodeSeq)
  copyNo(result, firstAstNode)
]#
# augassign: ('+=' | '-=' | '*=' | '@=' | '/=' | '%=' | '&=' | '|=' | '^=' |
#             '<<=' | '>>=' | '**=' | '//=')
ast augassign, [AsdlOperator]:
  assert parseNode.children.len == 1
  let augassignNode = parseNode.children[0]
  let token = augassignNode.tokenNode.token
  result = AsdlOperator(case token
  of Token.Plusequal: newAstAdd()
  of Token.Minequal:newAstSub()
  of Token.Starequal: newAstMult()
  of Token.Slashequal:newAstDiv()
  of Token.Percentequal: newAstMod()
  of Token.DoubleSlashequal: newAstFloorDiv()
  else:
    let msg = fmt"Complex augumented assign operation not implemented: " & $token
    raiseSyntaxError(msg)
  )


#[
Amperequal
Vbarequal
  Circumflexequal
  ]#

# del_stmt: 'del' exprlist
ast del_stmt, [AsdlStmt]:
  var node = newAstDelete()
  setNo(node, parseNode.children[0])
  let exprlist = parseNode.children[1]

  for i in astExprList(exprlist):
    node.targets.add(i)
    setDelete i
  node


# pass_stmt: 'pass'
ast pass_stmt, [AstPass]:
  result = newAstPass()
  setNo(result, parseNode.children[0])

# flow_stmt: break_stmt | continue_stmt | return_stmt | raise_stmt | yield_stmt
ast flow_stmt, [AsdlStmt]:
  let child = parseNode.children[0]
  childAst(child, result, 
    break_stmt,
    continue_stmt,
    return_stmt,
    raise_stmt,
    yield_stmt
  )
  assert result != nil


ast break_stmt, [AsdlStmt]:
  result = newAstBreak()
  setNo(result, parseNode.children[0])
  
ast continue_stmt, [AsdlStmt]:
  result = newAstContinue()
  setNo(result, parseNode.children[0])

# return_stmt: 'return' [testlist]
ast return_stmt, [AsdlStmt]:
  let node = newAstReturn()
  setNo(node, parseNode.children[0])
  if parseNode.children.len == 1:
    return node
  node.value = astTestList(parseNode.children[1])
  node
  
ast yield_stmt, [AsdlStmt]:
  raiseSyntaxError("Yield not implemented")
  
# raise_stmt: 'raise' [test ['from' test]]
ast raise_stmt, [AstRaise]:
  result = newAstRaise()
  setNo(result, parseNode.children[0])
  case parseNode.children.len
  of 1:
    discard
  of 2:
    result.exc = astTest(parseNode.children[1])
  else:
    raiseSyntaxError("Fancy raise not implemented", parseNode.children[2])


# import_stmt  import_name | import_from
ast import_stmt, [AsdlStmt]:
  let child = parseNode.children[0]
  case child.tokenNode.token 
  of Token.import_name:
    result = astImportName(child)
  of Token.import_from:
    raiseSyntaxError("Import from not implemented")
  else:
    unreachable("wrong import_stmt")

# import_name  'import' dotted_as_names
ast import_name, [AsdlStmt]:
  let node = newAstImport()
  setNo(node, parseNode.children[0])
  for c in parseNode.children[1].astDottedAsNames:
    node.names.add c
  node
  
  #[
ast import_from:
  discard
  
ast import_as_name:
  discard
]#

# dotted_as_name  dotted_name ['as' NAME]
ast dotted_as_name, [AstAlias]:
  if parseNode.children.len != 1:
    raiseSyntaxError("import alias not implemented")
  parseNode.children[0].astDottedName
  
  
#ast import_as_names:
#  discard

  
# dotted_as_names  dotted_as_name (',' dotted_as_name)*
ast dotted_as_names, [seq[AstAlias]]:
  if parseNode.children.len != 1:
    raiseSyntaxError("import multiple modules in one line not implemented", 
      parseNode.children[1])
  result.add parseNode.children[0].astDottedAsName
  
# dotted_name  NAME ('.' NAME)*
ast dotted_name, [AstAlias]:
  if parseNode.children.len != 1:
    raiseSyntaxError("dotted import name not supported", parseNode.children[1])
  result = newAstAlias()
  result.name = newIdentifier(parseNode.children[0].tokenNode.content)
  
proc astGlobalStmt(parseNode: ParseNode): AsdlStmt = 
  raiseSyntaxError("global stmt not implemented")
  
proc astNonlocalStmt(parseNode: ParseNode): AsdlStmt = 
  raiseSyntaxError("nonlocal stmt not implemented")
  
# assert_stmt  'assert' test [',' test]
ast assert_stmt, [AstAssert]:
  result = newAstAssert()
  setNo(result, parseNode.children[0])
  result.test = astTest(parseNode.children[1])
  if parseNode.children.len == 4:
    result.msg = astTest(parseNode.children[3])
  
# compound_stmt  if_stmt | while_stmt | for_stmt | try_stmt | with_stmt | funcdef | classdef | decorated | async_stmt
ast compound_stmt, [AsdlStmt]:
  let child = parseNode.children[0]
  childAst(child, result, 
    if_stmt,
    while_stmt,
    for_stmt,
    try_stmt,
    with_stmt,
    funcdef,
    classdef,
    decorated,
    async_stmt
    )
  assert result != nil
  
ast async_stmt, [AsdlStmt]:
  discard
  
# if_stmt  'if' test ':' suite ('elif' test ':' suite)* ['else' ':' suite]
ast if_stmt, [AstIf]:
  result = newAstIf()
  setNo(result, parseNode.children[0])
  result.test = astTest(parseNode.children[1])
  result.body = astSuite(parseNode.children[3])
  if parseNode.children.len == 4:  # simple if no else
    return
  if not (parseNode.children.len == 7):
    raiseSyntaxError("elif not implemented", parseNode.children[4])
  result.orelse = astSuite(parseNode.children[^1])
  
# while_stmt  'while' test ':' suite ['else' ':' suite]
ast while_stmt, [AstWhile]:
  result = newAstWhile()
  setNo(result, parseNode.children[0])
  result.test = astTest(parseNode.children[1])
  result.body = astSuite(parseNode.children[3])
  if not (parseNode.children.len == 4):
    raiseSyntaxError("Else clause in while not implemented", parseNode.children[4])

proc astExprListInFor(e: var AsdlExpr, node: ParseNode) =
  if not (node.children.len == 1):
    raiseSyntaxError("unpacking in for loop not implemented", node)
  let child = node.children[0]
  if not (child.tokenNode.token == Token.expr):
    raiseSyntaxError("unpacking in for loop not implemented", child)
  e = astExprList(node)[0]
  e.setStore
  # e=newTuple(astExprList(node))

# for_stmt  'for' exprlist 'in' testlist ':' suite ['else' ':' suite]
ast for_stmt, [AsdlStmt]:
  if not (parseNode.children.len == 6):
    raiseSyntaxError("for with else not implemented", parseNode.children[6])
  let forNode = newAstFor()
  setNo(forNode, parseNode.children[0])
  forNode.target.astExprListInFor(parseNode.children[1])
  forNode.iter = astTestlist(parseNode.children[3])
  forNode.body = astSuite(parseNode.children[5])
  result = forNode

#  try_stmt: ('try' ':' suite
#           ((except_clause ':' suite)+
#            ['else' ':' suite]
#            ['finally' ':' suite] |
#           'finally' ':' suite))
ast try_stmt, [AstTry]:
  result = newAstTry()
  setNo(result, parseNode.children[0])
  result.body = astSuite(parseNode.children[2])
  for i in 1..((parseNode.children.len-1) div 3):
    let child1 = parseNode.children[i*3]
    if not (child1.tokenNode.token == Token.except_clause):
      raiseSyntaxError("else/finally in try not implemented", child1)
    let handler = astExceptClause(child1)
    let child3 = parseNode.children[i*3+2]
    handler.body = astSuite(child3)
    result.handlers.add(handler)
  

ast with_stmt, [AsdlStmt]:
  raiseSyntaxError("with not implemented")
  
  #[
ast with_item:
  discard
  ]#

# except_clause: 'except' [test ['as' NAME]]
ast except_clause, [AstExceptHandler]:
  result = newAstExceptHandler()
  setNo(result, parseNode.children[0])
  case parseNode.children.len
  of 1:
    return
  of 2:
    result.type = astTest(parseNode.children[1])
  else:
    raiseSyntaxError("'except' with name not implemented", parseNode.children[2])
  

  

# suite  simple_stmt | NEWLINE INDENT stmt+ DEDENT
ast suite, [seq[AsdlStmt]]:
  case parseNode.children.len
  of 1:
    let child = parseNode.children[0]
    result = astSimpleStmt(child)
  else:
    for child in parseNode.children[2..^2]:
      result.addCompat(astStmt(child))
  assert result.len != 0
  for child in result:
    assert child != nil
  
# test  or_test ['if' or_test 'else' test] | lambdef
ast test, [AsdlExpr]:
  if not (parseNode.children.len == 1):
    raiseSyntaxError("Inline if else not implemented", parseNode.children[1])
  let child = parseNode.children[0]
  if not (child.tokenNode.token == Token.or_test):
    raiseSyntaxError("lambda not implemented")
  result = astOrTest(child)
  assert result != nil
  
  #[]
ast test_nocond:
  discard
  
ast lambdef:
  discard
  
ast lambdef_nocond:
  discard
  
  ]#

# help and or
template astForBoolOp(childAstFunc: untyped) = 
  assert parseNode.children.len mod 2 == 1
  let firstChild = parseNode.children[0]
  let firstAstNode = childAstFunc(firstChild)
  if parseNode.children.len == 1:
    return firstAstNode
  let token = parseNode.children[1].tokenNode.token
  var op: AsdlBoolop
  case token
  of Token.and:
    op = newAstAnd()
  of Token.or:
    op = newAstOr()
  else:
    unreachable
  var nodeSeq = @[firstAstNode]
  for idx in 1..parseNode.children.len div 2:
    let nextChild = parseNode.children[2 * idx]
    let nextAstNode = childAstFunc(nextChild)
    nodeSeq.add(nextAstNode)
  result = newBoolOp(op, nodeSeq)
  copyNo(result, firstAstNode)

# or_test  and_test ('or' and_test)*
ast or_test, [AsdlExpr]:
  astForBoolOp(astAndTest)
  
# and_test  not_test ('and' not_test)*
ast and_test, [AsdlExpr]:
  astForBoolOp(astNotTest)
  
# not_test 'not' not_test | comparison
ast not_test, [AsdlExpr]:
  let child = parseNode.children[0]
  case child.tokenNode.token
  of Token.not:
    result = newUnaryOp(newAstNot(), astNotTest(parsenode.children[1]))
    setNo(result, parseNode.children[0])
  of Token.comparison:
    result = astComparison(child)
  else:
    unreachable
  assert result != nil
  
# comparison  expr (comp_op expr)*
ast comparison, [AsdlExpr]:
  let expr1 = astExpr(parseNode.children[0])
  if parseNode.children.len == 1:
    result = expr1
    assert result != nil
    return
  if not (parseNode.children.len == 3):  # cases like a<b<c etc are NOT included
    raiseSyntaxError("Chained comparison not implemented", parseNode.children[2])
  let op = astCompOp(parseNode.children[1])
  let expr2 = astExpr(parseNode.children[2])
  let cmp = newAstCompare()
  cmp.left = expr1
  cmp.ops.add(op)
  cmp.comparators.add(expr2)
  copyNo(cmp, expr1)
  result = cmp
  assert result != nil

# comp_op  '<'|'>'|'=='|'>='|'<='|'<>'|'!='|'in'|'not' 'in'|'is'|'is' 'not'
ast comp_op, [AsdlCmpop]:
  let token = parseNode.children[0].tokenNode.token
  case token
  of Token.Less:
    result = newAstLt()
  of Token.Greater:
    result = newAstGt()
  of Token.Eqequal:
    result = newAstEq()
  of Token.GreaterEqual:
    result = newAstGtE()
  of Token.LessEqual:
    result = newAstLtE()
  of Token.NotEqual:
    result = newAstNotEq()
  of Token.in:
    result = newAstIn()
  of Token.not:
    result = newAstNotIn()
  else:
    raiseSyntaxError(fmt"Complex comparison operation {token} not implemented")
#  
#ast star_expr:
#  discard
  
# help expr, xor_expr, and_expr, shift_expr, arith_expr, term
template astForBinOp(childAstFunc: untyped) = 
  assert parseNode.children.len mod 2 == 1
  let firstChild = parseNode.children[0]
  let firstAstNode = childAstFunc(firstChild)
  result = firstAstNode
  for idx in 1..parseNode.children.len div 2:
    let opParseNode = parseNode.children[2 * idx - 1]
    let token = opParseNode.tokenNode.token
    let op = AsdlOperator(case token
    of Token.Plus: newAstAdd()
    of Token.Minus:newAstSub()
    of Token.Star: newAstMult()
    of Token.Slash:newAstDiv()
    of Token.Percent: newAstMod()
    of Token.DoubleSlash: newAstFloorDiv()
    else:
      let msg = fmt"Complex binary operation not implemented: " & $token
      raiseSyntaxError(msg)
    )

    let secondChild = parseNode.children[2 * idx]
    let secondAstNode = childAstFunc(secondChild)
    result = newBinOp(result, op, secondAstNode)
    setNo(result, opParseNode)


# expr  xor_expr ('|' xor_expr)*
ast expr, [AsdlExpr]:
  astForBinOp(astXorExpr)
  
# xor_expr  and_expr ('^' and_expr)*
ast xor_expr, [AsdlExpr]:
  astForBinOp(astAndExpr)
  
# and_expr  shift_expr ('&' shift_expr)*
ast and_expr, [AsdlExpr]:
  astForBinOp(astShiftExpr)
  
# shift_expr  arith_expr (('<<'|'>>') arith_expr)*
ast shift_expr, [AsdlExpr]:
  astForBinOp(astArithExpr)
  
# arith_expr  term (('+'|'-') term)*
ast arith_expr, [AsdlExpr]:
  astForBinOp(astTerm)
  
# term  factor (('*'|'@'|'/'|'%'|'//') factor)*
ast term, [AsdlExpr]:
  astForBinOp(astFactor)
  
# factor  ('+'|'-'|'~') factor | power
ast factor, [AsdlExpr]:
  case parseNode.children.len
  of 1:
    let child = parseNode.children[0]
    result = astPower(child)
  of 2:
    let child1 = parseNode.children[0]
    let factor = astFactor(parseNode.children[1])
    case child1.tokenNode.token
    of Token.Plus:
      result = newUnaryOp(newAstUAdd(), factor)
    of Token.Minus:
      result = newUnaryOp(newAstUSub(), factor)
    else:
      raiseSyntaxError("Unary ~ not implemented", child1)
    setNo(result, parseNode.children[0])
  else:
    unreachable
    
# power  atom_expr ['**' factor]
proc astPower(parseNode: ParseNode): AsdlExpr = 
  let child = parseNode.children[0]
  let base = astAtomExpr(child)
  if len(parseNode.children) == 1:
    result = base
  else:
    let exp = astFactor(parseNode.children[2])
    result = newBinOp(base, newAstPow(), exp)
    setNo(result, parseNode.children[1])
  
# atom_expr  ['await'] atom trailer*
proc astAtomExpr(parseNode: ParseNode): AsdlExpr = 
  let child = parseNode.children[0]
  if child.tokenNode.token == Token.await:
    raiseSyntaxError("Await not implemented", child)
  result = astAtom(child)
  if parseNode.children.len == 1:
    return
  for trailerChild in parseNode.children[1..^1]:
    result = astTrailer(trailerChild, result)
  
# atom: ('(' [yield_expr|testlist_comp] ')' |
#      '[' [testlist_comp] ']' |
#      '{' [dictorsetmaker] '}' |
#      NAME | NUMBER | STRING+ | '...' | 'None' | 'True' | 'False')
ast atom, [AsdlExpr]:
  let child1 = parseNode.children[0]
  case child1.tokenNode.token
  of Token.Lpar:
    case parseNode.children.len
    of 2:
      result = newTuple(@[])
    of 3:
      let child = parseNode.children[1]
      case child.tokenNode.token
      of Token.yield_expr:
        raiseSyntaxError("Yield expression not implemented", child)
      of Token.testlist_comp:
        let testListComp = astTestlistComp(child)
        # 1-element tuple or things like (1 + 2) * 3
        if testListComp.len == 1 and not (
            child.children.len == 2 and  # 1-element tuple. e.g. (1,)
            child.children[1].tokenNode.token == Token.Comma
        ):
          if testListComp[0].kind == AsdlExprTk.ListComp:
            raiseSyntaxError("generator expression not implemented", child)
          result = testListComp[0]
        else:
          result = newTuple(testListComp)
      else:
        unreachable   
    else:
      unreachable

  of Token.Lsqb:
    case parseNode.children.len
    of 2:
      result = newList(@[])
    of 3:
      let contents = astTestlistComp(parseNode.children[1])
      if contents.len == 1 and contents[0].kind == AsdlExprTk.ListComp:
        result = contents[0]
      else:
        result = newList(contents)
    else:
      unreachable

  of Token.Lbrace:
    case parseNode.children.len
    of 2:
      result = newAstDict()
    of 3:
      result = astDictOrSetMaker(parseNode.children[1])
    else:
      unreachable # {} blocked in lexer

  of Token.NAME:
    result = newAstName(child1.tokenNode)

  of Token.NUMBER:
    # float
    if not child1.tokenNode.content.allCharsInSet({'0'..'9'}):
      let f = parseFloat(child1.tokenNode.content)
      let pyFloat = newPyFloat(f)
      result = newAstConstant(pyFloat)
    # int
    else:
      let pyInt = newPyInt(child1.tokenNode.content)
      result = newAstConstant(pyInt)

  of Token.STRING:
    var str: string
    for child in parseNode.children:
      str.add(child.tokenNode.content)
    let pyString = newPyString(str)
    result = newAstConstant(pyString)

  of Token.True:
    result = newAstConstant(pyTrueObj)

  of Token.False:
    result = newAstConstant(pyFalseObj)

  of Token.None:
    result = newAstConstant(pyNone)

  of Token.Ellipsis:
    result = newAstConstant(pyEllipsis)
  else:
    unreachable()

  assert result != nil
  setNo(result, parseNode.children[0])
  

# testlist_comp  (test|star_expr) ( comp_for | (',' (test|star_expr))* [','] )
# currently only used in atom
ast testlist_comp, [seq[AsdlExpr]]:
  # return type: if comprehension, a seq with only one element: AstListComp
  # or a seq with comma separated elements
  let child1 = parseNode.children[0]
  if child1.tokenNode.token == Token.star_expr:
    raiseSyntaxError("Star expression not implemented", child1)
  let test1 = astTest(child1)
  # comprehension
  if (parseNode.children.len == 2) and 
      (parseNode.children[1].tokenNode.token == Token.comp_for):
    let listComp = newAstListComp()
    # no need to care about setting lineNo and colOffset, because `atom` does so
    listComp.elt = test1
    listComp.generators = astCompFor(parseNode.children[1])
    result.add listComp
    return
  # comma separated items
  result.add test1
  for child in parseNode.children[1..^1]:
    case child.tokenNode.token
    of Token.Comma:
      discard
    of Token.test:
      result.add astTest(child)
    of Token.star_expr:
      raiseSyntaxError("Star expression not implemented", child)
    else:
      unreachable
  
# trailer  '(' [arglist] ')' | '[' subscriptlist ']' | '.' NAME
ast trailer, [AsdlExpr, leftExpr: AsdlExpr]:
  case parseNode.children[0].tokenNode.token
  of Token.Lpar:
    var callNode = newAstCall()
    callNode.fun = leftExpr
    case parseNode.children.len
    of 2:
      result = callNode 
    of 3:
      result = astArglist(parseNode.children[1], callNode)
    else:
      unreachable
  of Token.Lsqb:
    let sub = newAstSubscript()
    sub.value = leftExpr
    sub.slice = astSubscriptlist(parseNode.children[1])
    sub.ctx = newAstLoad()
    result = sub
  of Token.Dot:
    let attr = newAstAttribute()
    attr.value = leftExpr
    attr.attr = newIdentifier(parseNode.children[1].tokenNode.content)
    attr.ctx = newAstLoad()
    result = attr
  else:
    unreachable
  setNo(result, parseNode.children[0])
  
# subscriptlist: subscript (',' subscript)* [',']
ast subscriptlist, [AsdlSlice]:
  if not parseNode.children.len == 1:
    raiseSyntaxError("subscript only support one index", parseNode.children[1])
  parseNode.children[0].astSubscript
  
# subscript: test | [test] ':' [test] [sliceop]
# sliceop: ':' [test]
ast subscript, [AsdlSlice]:
  let child1 = parseNode.children[0]
  if (child1.tokenNode.token == Token.test) and parseNode.children.len == 1:
    let index = newAstIndex()
    index.value = astTest(child1)
    return index
  # slice
  let slice = newAstSlice()
  # lower
  var idx = 0
  var child = parseNode.children[idx]
  if child.tokenNode.token == Token.test:
    slice.lower = astTest(child)
    idx += 2
  else:
    assert child.tokenNode.token == Token.Colon
    inc idx
  if idx == parseNode.children.len:
    return slice
  # upper
  child = parseNode.children[idx]
  if child.tokenNode.token == Token.test:
    slice.upper = astTest(child)
    inc idx
  if idx == parseNode.children.len:
    return slice
  child = parseNode.children[idx]
  # step
  assert child.tokenNode.token == Token.sliceop
  if child.children.len == 2:
    slice.step = astTest(child.children[1])
  slice


# exprlist: (expr|star_expr) (',' (expr|star_expr))* [',']
ast exprlist, [seq[AsdlExpr]]:
  ## current `ast star_expr` not impl
  for i in 0..<((parseNode.children.len + 1) div 2):
    let child = parseNode.children[2*i]
    result.add astExpr(child)

# testlist: test (',' test)* [',']
ast testlist, [AsdlExpr]:
  var elms: seq[AsdlExpr]
  for i in 0..<((parseNode.children.len + 1) div 2):
    let child = parseNode.children[2 * i]
    elms.add ast_test(child)
  if parseNode.children.len == 1:
    result = elms[0]
  else:
    result = newTuple(elms)
    copyNo(result, elms[0])
  assert result != nil


#   dictorsetmaker: ( ((test ':' test | '**' expr)
#                   (comp_for | (',' (test ':' test | '**' expr))* [','])) |
#                  ((test | star_expr)
#                   (comp_for | (',' (test | star_expr))* [','])) )
ast dictorsetmaker, [AsdlExpr]:
  let children = parseNode.children
  let le = children.len
  if le == 0:  # {} -> dict()
    return newAstDict()
  elif le == 1:
    let s = newAstSet()
    s.elts.add astTest children[0]
    return s
  # Then `children[1]` won't go out of bound
  let leFix = le + 1  # XXX: + 1 to add tailing comma. So for list,etc. FIXME: allow trailing comma
  let isDict = children[1].tokenNode.token == Token.Colon
  # no need to care about setting lineNo and colOffset, because `atom` does so
  if isDict:
    let d = newAstDict()
    for idx in 0..<(leFix div 4):
      let i = idx * 4
      if children.len < i + 3:
        raiseSyntaxError("dict definition too complex (no comprehension)")
      let c1 = children[i]
      if not (c1.tokenNode.token == Token.test):
        raiseSyntaxError("dict definition too complex (no comprehension)", c1)
      d.keys.add(astTest(c1))
      if not (children[i+1].tokenNode.token == Token.Colon):
        raiseSyntaxError("dict definition too complex (no comprehension)")
      let c3 = children[i+2]
      if not (c3.tokenNode.token == Token.test):
        raiseSyntaxError("dict definition too complex (no comprehension)", c3)
      d.values.add(astTest(c3))
    result = d
  else:
    let s = newAstSet()
    for i in 0..<(leFix div 2):
      let c = children[i * 2]
      s.elts.add(astTest(c))
    result = s

  
# classdef: 'class' NAME ['(' [arglist] ')'] ':' suite
ast classdef, [AstClassDef]:
  if parseNode.children.len != 4:
    raiseSyntaxError("inherit not implemented", parseNode.children[4])
  result = newAstClassDef()
  setNo(result, parseNode.children[0])
  result.name = newIdentifier(parseNode.children[1].tokenNode.content)
  result.body = astSuite(parseNode.children[^1])
  
# arglist  argument (',' argument)*  [',']
ast arglist, [AstCall, callNode: AstCall]:
  # currently assume `argument` only has simplest `test`, e.g.
  # print(1,3,4), so we can do this
  for child in parseNode.children: 
    if child.tokenNode.token == Token.argument:
      callNode.args.add(astArgument(child))
  callNode
  
# argument  ( test [comp_for] | test '=' test | '**' test | '*' test  )
ast argument, [AsdlExpr]:
  if not (parseNode.children.len == 1):
    raiseSyntaxError("Only simple identifiers for function argument", 
      parseNode.children[1])
  let child = parseNode.children[0]
  result = astTest(child)
  assert result != nil

#ast comp_iter:
#  discard

# sync_comp_for: 'for' exprlist 'in' or_test [comp_iter]
ast sync_comp_for, [seq[AsdlComprehension]]:
  if parseNode.children.len == 5:
    raiseSyntaxError("Complex comprehension not implemented", parseNode.children[5])
  let comp = newAstComprehension()
  comp.target.astExprListInFor(parseNode.children[1])
  comp.iter = astOrTest(parseNode.children[3])
  result.add comp
  
  
# comp_for: ['async'] sync_comp_for
ast comp_for, [seq[AsdlComprehension]]:
  if parseNode.children.len == 2:
    raiseSyntaxError("Async comprehension not implemented", parseNode.children[0])
  return astSyncCompFor(parseNode.children[0])

  
#ast comp_if:
#  discard
  
#[
ast encoding_decl:
  discard
  
ast yield_expr:
  discard
  
ast yield_arg:
  discard
]#

proc ast*(root: ParseNode): AsdlModl = 
  case root.tokenNode.token
  of Token.file_input:
    result = astFileInput(root)
  of Token.single_input:
    result = astSingleInput(root)
  of Token.eval_input:
    unreachable  # currently no eval mode
  else:
    unreachable
  when defined(debug):
    echo result

proc ast*(input, fileName: string): AsdlModl= 
  let root = parse(input, fileName)
  try:
    result = ast(root)
  except SyntaxError:
    let e = getCurrentException()
    SyntaxError(e).fileName = fileName
    raise e
