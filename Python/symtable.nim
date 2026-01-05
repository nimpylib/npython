import tables

import sets
import macros

import ast
import asdl
import ../Objects/noneobject
import ../Objects/pyobjectBase
import ../Objects/stringobject
import ../Utils/utils

type
  Scope* {. pure .} = enum
    Local,
    Cell,
    Free,
    Global

  SteKind* {. pure .} = enum
    Module, Function, Class

type
  SymTable* = ref object
    # map ast node address to ste
    entries: Table[AstNodeBase, SymTableEntry]
    root: SymTableEntry

  SymTableEntry* = ref object
    # the symbol table entry tree
    parent: SymTableEntry
    children: seq[SymTableEntry]
    kind*: SteKind

    # function arguments, name to index in argument list
    argVars*: Table[PyStrObject, int]
    varArg*: PyStrObject
    kwOnlyArgs*: seq[PyStrObject]
    kwOnlyDefaults*: seq[PyObject]

    declaredVars: HashSet[PyStrObject]
    usedVars: HashSet[PyStrObject]

    globals: HashSet[PyStrObject] ## names in global stmt
    nonlocals: HashSet[PyStrObject] ## names in nonlocal stmt
    # for scope lookup
    scopes: Table[PyStrObject, Scope]

    # the difference between names and localVars is subtle.
    # In runtime, py object in names are looked up in local
    # dict and global dict by string key. 
    # At least global dict can be modified dynamically. 
    # whereas py object in localVars are looked up in var
    # sequence, thus faster. localVar can't be made global
    # def foo(x):
    #   global x
    # will result in an error (in CPython)
    # names also responds for storing attribute names
    names: Table[PyStrObject, int]
    localVars: Table[PyStrObject, int]
    # used for closures
    cellVars: Table[PyStrObject, int]  # declared in the scope
    freeVars: Table[PyStrObject, int]  # not declared in the scope

proc newSymTableEntry(parent: SymTableEntry): SymTableEntry =
  result = new SymTableEntry
  result.parent = parent
  if not parent.isNil: # not root
    parent.children.add result
  result.argVars = initTable[PyStrObject, int]()
  result.declaredVars = initHashSet[PyStrObject]()
  result.usedVars = initHashSet[PyStrObject]()
  result.scopes = initTable[PyStrObject, Scope]()
  result.names = initTable[PyStrObject, int]()
  result.localVars = initTable[PyStrObject, int]()
  result.cellVars = initTable[PyStrObject, int]()
  result.freeVars = initTable[PyStrObject, int]()

{. push inline, cdecl .}

proc getSte*(st: SymTable, key: AstNodeBase): SymTableEntry{.raises: [].} = 
  KeyError!st.entries[key]

proc isRootSte(ste: SymTableEntry): bool = 
  ste.parent.isNil

proc declared(ste: SymTableEntry, localName: PyStrObject): bool =
  localName in ste.declaredVars

proc getScope*(ste: SymTableEntry, name: PyStrObject): Scope = 
  ste.scopes[name]

proc addDeclaration(ste: SymTableEntry, name: PyStrObject) =
  ste.declaredVars.incl name

proc addDeclaration(ste: SymTableEntry, name: AsdlIdentifier) =
  let nameStr = name.value
  ste.addDeclaration nameStr

proc rmDeclaration(ste: SymTableEntry, name: PyStrObject) =
  ste.declaredVars.excl name
proc rmDeclaration(ste: SymTableEntry, name: AsdlIdentifier) =
  ste.rmDeclaration(name.value)

proc addUsed(ste: SymTableEntry, name: PyStrObject) =
  ste.usedVars.incl name

proc addUsed(ste: SymTableEntry, name: AsdlIdentifier) =
  let nameStr = name.value
  ste.addUsed(nameStr)

proc localId*(ste: SymTableEntry, localName: PyStrObject): int =
  ste.localVars[localName]

proc nameId*(ste: SymTableEntry, nameStr: PyStrObject): int =
  # add entries for attribute lookup
  ste.names.withValue(nameStr, value):
    return value[]
  do:
    result = ste.names.len
    ste.names[nameStr] = result

proc cellId*(ste: SymTableEntry, nameStr: PyStrObject): int = 
  ste.cellVars[nameStr]

proc freeId*(ste: SymTableEntry, nameStr: PyStrObject): int = 
  # they end up in the same seq
  ste.freeVars[nameStr] + ste.cellVars.len

proc hasCell*(ste: SymTableEntry, nameStr: PyStrObject): bool = 
  ste.cellVars.hasKey(nameStr)

proc hasFree*(ste: SymTableEntry, nameStr: PyStrObject): bool = 
  ste.freeVars.hasKey(nameStr)

proc toInverseSeq(t: Table[PyStrObject, int]): seq[PyStrObject] =
  result = newSeq[PyStrObject](t.len)
  for name, id in t:
    result[id] = name

proc namesToSeq*(ste: SymTableEntry): seq[PyStrObject] = 
  ste.names.toInverseSeq

proc localVarsToSeq*(ste: SymTableEntry): seq[PyStrObject] = 
  ste.localVars.toInverseSeq

proc cellVarsToSeq*(ste: SymTableEntry): seq[PyStrObject] = 
  ste.cellVars.toInverseSeq

proc freeVarsToSeq*(ste: SymTableEntry): seq[PyStrObject] = 
  ste.freeVars.toInverseSeq

{. pop .}

# traverse the ast to collect local vars
# local vars can be defined in Name List Tuple For Import
# currently we only have Name, For, Import, so it's pretty simple. 
# lot's of discard out there, because we want to quit early if something
# goes wrong. In future when the symtable is basically done these codes
# can probably be deleted
# Note that Assert implicitly uses name "AssertionError"

proc collectDeclaration*(st: SymTable, astRoot: AsdlModl){.raises: [SyntaxError].} = 
  var toVisit: seq[(AstNodeBase, SymTableEntry)]
  toVisit.add((AstNodeBase astRoot, SymTableEntry nil))

  proc visitArgs(argsNode: AsdlArguments, ste: SymTableEntry){.nimcall.} =  
    let args = AstArguments(argsNode)
    # positional args
    for idx, arg in args.args:
      assert arg of AstArg
      ste.addDeclaration(AstArg(arg).arg)
      ste.argVars[AstArg(arg).arg.value] = idx
    # vararg
    if not args.vararg.isNil:
      let v = AstArg(args.vararg)
      ste.varArg = v.arg.value
      ste.addDeclaration(v.arg)
    # keyword-only args
    for k in args.kwonlyargs:
      let ka = AstArg(k)
      ste.kwOnlyArgs.add ka.arg.value
      ste.addDeclaration(ka.arg)
    # placeholder for kw-only defaults evaluated during compile
    ste.kwOnlyDefaults = newSeq[PyObject](args.kw_defaults.len)
    for i in 0..<args.kw_defaults.len:
      ste.kwOnlyDefaults[i] = pyNone

  while toVisit.len != 0:
    let (astNode, parentSte) = toVisit.pop
    let ste = newSymTableEntry(parentSte)
    st.entries[astNode] = ste
    var toVisitPerSte: seq[AstNodeBase]
    template visitInNewBlock(astNode: AstNodeBase) =
      toVisit.add((astNode, ste))
    template visit(n) = 
      if not n.isNil:
        toVisitPerSte.add n
    template visitSeq(s) =
      for astNode in s:
        toVisitPerSte.add(astNode)
    template visitKeywords(keywords: seq[Asdlkeyword]) =
      for k in keywords:
        visit k.value

    template addBodies(TypeName) = 
      for node in TypeName(astNode).body:
        toVisitPerSte.add(node)
    # these asts mean new scopes
    if astNode of AstModule:
      ste.kind = SteKind.Module
      addBodies(AstModule)
    elif astNode of AstInteractive:
      ste.kind = SteKind.Module
      addBodies(AstInteractive)
    elif astNode of AstFunctionDef:
      ste.kind = SteKind.Function
      # deal with function args
      let f = AstFunctionDef(astNode)
      visitArgs f.args, ste
      addBodies(AstFunctionDef)
    elif astNode of AstClassDef:
      ste.kind = SteKind.Class
      addBodies(AstClassDef)

    elif astNode of AstLambda:
      ste.kind = SteKind.Function
      # deal with function args
      let f = AstLambda(astNode)
      visitArgs f.args, ste
      visit f.body
    else:

      # comprehensions
      ste.kind = SteKind.Function
      template prepareCompSte(kind; doWithNode){.dirty.} =
        let compNode = kind(astNode)
        doWithNode
        for gen in compNode.generators:
          let genNode = AstComprehension(gen)
          toVisitPerSte.add(genNode.target)
        # the iterator. Need to add here to let symbol table make room for the localVar
      template prepareCompSte(kind){.dirty.} =
        prepareCompSte(kind):
          toVisitPerSte.add compNode.elt

      if astNode of AstListComp:
        prepareCompSte(AstListComp)
      elif astNode of AstSetComp:
        prepareCompSte(AstSetComp)
      elif astNode of AstDictComp:
        prepareCompSte(AstDictComp):
          toVisitPerSte.add compNode.key
          toVisitPerSte.add compNode.value
      else: unreachable

      let zero = newPyAscii".0"
      ste.addDeclaration(zero)
      ste.argVars[zero] = 0

    while toVisitPerSte.len != 0:
      let astNode = toVisitPerSte.pop
      template doSeqIt(itor; itExpr){.dirty.} =
          for it in itor: itExpr
      template doSeqItFromNames(T; itExpr){.dirty.} =
        doSeqIt `Ast T`(astNode).names, itExpr
      if astNode of AsdlStmt:
        case AsdlStmt(astNode).kind

        of AsdlStmtTk.FunctionDef:
          let funcNode = AstFunctionDef(astNode)
          ste.addDeclaration(funcNode.name)
          visitInNewBlock astNode
          visitSeq(funcNode.decorator_list)

        of AsdlStmtTk.ClassDef:
          let classNode = AstClassDef(astNode)
          visitSeq classNode.bases
          assert classNode.keywords.len == 0
          assert classNode.decoratorList.len == 0
          ste.addDeclaration(classNode.name)
          visitInNewBlock astNode

        of AsdlStmtTk.Return:
          visit AstReturn(astNode).value

        of AsdlStmtTk.Assign:
          let assignNode = AstAssign(astNode)
          assert assignNode.targets.len == 1
          visit assignNode.targets[0]
          visit assignNode.value

        of AsdlStmtTk.AugAssign:
          let binOpNode = AstAugAssign(astNode)
          visit binOpNode.target
          visit binOpNode.value

        of AsdlStmtTk.Delete:
          let binOpNode = AstDelete(astNode)
          visitSeq binOpNode.targets

        of AsdlStmtTk.For:
          let forNode = AstFor(astNode)
          if not (forNode.target.kind == AsdlExprTk.Name):
            raiseSyntaxError("only name as loop variable", forNode.target)
          visit forNode.target
          visit forNode.iter
          visitSeq(forNode.body)
          assert forNode.orelse.len == 0

        of AsdlStmtTk.While:
          let whileNode = AstWhile(astNode)
          visit whileNode.test
          visitSeq(whileNode.body)
          assert whileNode.orelse.len == 0

        of AsdlStmtTk.If:
          let ifNode = AstIf(astNode)
          visit ifNode.test
          visitSeq(ifNode.body)
          visitSeq(ifNode.orelse)

        of AsdlStmtTk.Raise:
          let raiseNode = AstRaise(astNode)
          visit raiseNode.exc
          visit raiseNode.cause

        of AsdlStmtTk.Assert:
          let assertNode = AstAssert(astNode)
          ste.addUsed(newPyAscii("AssertionError"))
          visit assertNode.test
          visit assertNode.msg

        of AsdlStmtTk.Try:
          let tryNode = AstTry(astNode)
          visitSeq(tryNode.body)
          visitSeq(tryNode.handlers)
          visitSeq(tryNode.orelse)
          visitSeq(tryNode.finalbody)
        
        of AsdlStmtTk.With:
          let withNode = AstWith(astNode)
          for item in withNode.items:
            let withItem = AstWithitem(item)
            visit withItem.context_expr
            visit withItem.optional_vars
          visitSeq(withNode.body)

        of AsdlStmtTk.Import:
          doSeqItFromNames Import:
            ste.addDeclaration(AstAlias(it).asname)
        of AsdlStmtTk.ImportFrom:
          doSeqItFromNames ImportFrom:
            ste.addDeclaration(AstAlias(it).asname)
        of AsdlStmtTk.Global:
          doSeqItFromNames Global:
            let name = it.value
            if name in ste.nonlocals:
              raiseSyntaxError("name '" & $name & "' is nonlocal and global", AstGlobal astNode)
            ste.globals.incl name
        of AsdlStmtTk.Nonlocal:
          if ste.kind == SteKind.Module:
             raiseSyntaxError("nonlocal declaration not allowed at module level", AstNonlocal astNode)
          doSeqItFromNames Nonlocal:
            let name = it.value
            if name in ste.globals:
              raiseSyntaxError("name '" & $name & "' is nonlocal and global", AstNonlocal astNode)
            ste.nonlocals.incl name
        of AsdlStmtTk.Expr:
          visit AstExpr(astNode).value

        of AsdlStmtTk.Pass, AsdlStmtTk.Break, AsdlStmtTk.Continue:
          discard
        else:
          unreachable($AsdlStmt(astNode).kind)
      elif astNode of AsdlExpr:

        template prepareCompBody(compNode){.dirty.} =
          visitInNewBlock astNode
          for gen in compNode.generators:
            let genNode = AstComprehension(gen)
            visit genNode.iter
            visit genNode.target
        template prepareComp(kind){.dirty.} =
          # tricky here. Parts in this level, parts in a new function
          let compNode = kind(astNode)
          visit compNode.elt
          prepareCompBody compNode
        case AsdlExpr(astNode).kind

        of AsdlExprTk.BoolOp:
          visitSeq AstBoolOp(astNode).values

        of AsdlExprTk.BinOp:
          let binOpNode = AstBinOp(astNode)
          visit binOpNode.left
          visit binOpNode.right

        of AsdlExprTk.UnaryOp:
          visit AstUnaryOp(astNode).operand

        of AsdlExprTk.Dict:
          let dictNode = AstDict(astNode)
          visitSeq dictNode.keys
          visitSeq dictNode.values

        of AsdlExprTk.Set:
          let setNode = AstSet(astNode)
          visitSeq setNode.elts

        of AsdlExprTk.ListComp: prepareComp(AstListComp)
 
        of AsdlExprTk.SetComp: prepareComp(AstSetComp)

        of AsdlExprTk.DictComp:
          let dcomp = AstDictComp(astNode)
          visit dcomp.key
          visit dcomp.value
          prepareCompBody(dcomp)

        of AsdlExprTk.Compare:
          let compareNode = AstCompare(astNode)
          visit compareNode.left
          visitSeq compareNode.comparators

        of AsdlExprTk.Call:
          let callNode = AstCall(astNode)
          visit callNode.fun
          visitSeq callNode.args
          #TODO:check_name callNode.keywords
          visitKeywords callNode.keywords

        of AsdlExprTk.Attribute:
          visit AstAttribute(astNode).value
        
        of AsdlExprTk.Subscript:
          let subsNode = AstSubscript(astNode)
          visit subsNode.value
          visit subsNode.slice

        of AsdlExprTk.Name:
          let nameNode = AstName(astNode)
          case nameNode.ctx.kind
          of AsdlExprContextTk.Store:
            ste.addDeclaration(nameNode.id)
          of AsdlExprContextTk.Load:
            ste.addUsed(nameNode.id)
          of AsdlExprContextTk.Del:
            #ste.rmDeclaration(nameNode.id)
            # TODO: don't rm decl, but what to do?
            discard
          else:
            unreachable

        of AsdlExprTk.IfExp:
          let ifExpr = AstIfExp(astNode)
          visit ifExpr.test
          visit ifExpr.body
          visit ifExpr.orelse

        of AsdlExprTk.List:
          let listNode = AstList(astNode)
          case listNode.ctx.kind
          of AsdlExprContextTk.Store, AsdlExprContextTk.Load:
            visitSeq listNode.elts
          else:
            unreachable

        of AsdlExprTk.Tuple:
          let tupleNode = AstTuple(astNode)
          case tupleNode.ctx.kind
          of AsdlExprContextTk.Store, AsdlExprContextTk.Load:
            visitSeq tupleNode.elts
          else:
            unreachable

        of AsdlExprTk.Constant:
          discard

        of AsdlExprTk.Lambda:
          #ste.addDeclaration(pyId "<lambda>")
          visitInNewBlock astNode
        else:
          unreachable

      elif astNode of AsdlSlice:
        case AsdlSlice(astNode).kind
        
        of AsdlSliceTk.Slice:
          let sliceNode = AstSlice(astNode)
          visit sliceNode.lower
          visit sliceNode.upper
          visit sliceNode.step

        of AsdlSliceTk.ExtSlice:
          unreachable

        of AsdlSliceTk.Index:
          visit AstIndex(astNode).value

      elif astNode of AsdlExceptHandler:
        let excpNode = AstExcepthandler(astNode)
        if not excpNode.name.isNil:
          ste.addDeclaration(excpNode.name)
        visitSeq(excpNode.body)
        visit(excpNode.type)
      else:
        unreachable()

proc determineScope(ste: SymTableEntry, name: PyStrObject) = 
  if ste.scopes.hasKey(name):
    return
  
  let isNonlocal = name in ste.nonlocals

  template lookup(entry; setsco) =
    if entry.isRootSte or name in entry.globals:
      setsco Scope.Global
    if (entry == ste or entry.kind != SteKind.Class) and entry.declared(name):
      if name in entry.nonlocals:
        discard
      else:
        setsco Scope.Local
  template update_and_ret(sco) =
    ste.scopes[name] = sco
    return
  lookup ste, update_and_ret
  var traceback = @[ste, ste.parent]
  var scope: Scope
  while true:
    let curSte = traceback[^1]
    if curSte.isNil:
      traceback.setLen(traceback.len - 1)
      break
    template set_and_break(sco) =
      scope = sco
      break
    lookup curSte, set_and_break
    traceback.add curSte.parent
  
  #TODO:nonlocal
  #if isNonlocal and scope == Scope.Global:
  #   raiseSyntaxError("no binding for nonlocal '" & $name & "' found", nil)

  traceback[^1].scopes[name] = scope
  case scope
  of Scope.Cell:
    scope = Scope.Free
  of Scope.Global:
    discard
  of Scope.Local:
    traceback[^1].scopes[name] = Scope.Cell
    scope = Scope.Free
  else:
    unreachable
  for curSte in traceback[0..^2]:
    curSte.scopes[name] = scope

proc determineScope(ste: SymTableEntry) =
  # DFS ensures proper closure behavior (cells and frees correctly determined)
  for child in ste.children:
    child.determineScope()
  for name in ste.usedVars:
    ste.determineScope(name)
  # for those not set as cell or free, determine local or global
  for name in ste.declaredVars:
    ste.determineScope(name)
  # setup the indeces
  for name, scope in ste.scopes.pairs:
    var d: ptr Table[PyStrObject, int]
    case scope
    of Scope.Local:
      d = ste.localVars.addr
    of Scope.Global:
      d = ste.names.addr
    of Scope.Cell:
      d = ste.cellVars.addr
    of Scope.Free:
      d = ste.freeVars.addr
    d[][name] = d[].len

proc determineScope(st: SymTable) = 
  st.root.determineScope

proc newSymTable*(astRoot: AsdlModl): SymTable{.raises: [SyntaxError].} = 
  new result
  result.entries = initTable[AstNodeBase, SymTableEntry]()
  # traverse ast tree for 2 passes for symbol scopes
  # first pass
  result.collectDeclaration(astRoot)
  result.root = result.getSte(astRoot)
  # second pass
  result.determineScope()
