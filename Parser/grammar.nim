when defined(nimPreviewSlimSystem):
  import std/assertions

import strutils
import algorithm
import hashes
import parseutils
import sequtils
import strformat
import sets
import tables
import deques

import token
import ../Utils/[compat]


type
  Repeat* {.pure.} = enum
    None
    Star
    Plus
    Query

  GrammarNode* = ref object
    id: int
    father*: GrammarNode
    repeat*: Repeat
    epsilonSet*: HashSet[GrammarNode] # grammar nodes reachable by \epsilon operaton
    case kind*: char
    of 'a', 's': # terminal and dummy sentinel
      token*: Token
      nextSet*: HashSet[GrammarNode]
    of 'A'..'H': # non-terminal
      children*: seq[GrammarNode]
    else: # + * ?
      discard

  Grammar = ref object
    token: Token
    grammarString: string
    rootNode*: GrammarNode
    firstSet*: set[Token]
    cursor: int


const
  grammarFilepath = "Grammar"
  grammarLines = slurp(grammarFilepath).splitLines()


var 
  grammarSet* =  initTable[Token, Grammar]()
  firstSet = initTable[Token, set[Token]]()

proc `$`*(grammarNode: GrammarNode): string

# Grammar of EBNF used in python
# ast: a seq of B with E as attribute, if only one element, factored to one B with E
# A -> B E H                               
# B -> C | D | a                           ast: C or D or reserved name or grammar token
# C -> '[' F ']'                           ast: a seq of A by expanding F
# ast: same as above, rename to F, D info in attribute
# D -> '(' F ')'                           
# E -> + | * | \epsilon
# F -> A G                                 ast: a seq of A, if only one element, factored 
# G -> '|' A G | \epsilon                  ast: a seq of A
# H -> A | \epsilon                        ast: nil or single A
#
# Resulting AST only contains A F and a (sometimes with s as sentinel)
# A stands for a sequence of stmt
# F stands for an Or sequence
# a is (grammar) terminator

proc matchA(grammar: Grammar): GrammarNode  
proc matchB(grammar: Grammar): GrammarNode  
proc matchC(grammar: Grammar): GrammarNode  
proc matchD(grammar: Grammar): GrammarNode  
proc matchE(grammar: Grammar): GrammarNode  
proc matchF(grammar: Grammar): GrammarNode  
proc matchG(grammar: Grammar): GrammarNode  
proc matchH(grammar: Grammar): GrammarNode  

proc newGrammarNode(name: char, tokenString=""): GrammarNode 
proc hash(node: GrammarNode): Hash{.raises: [].}
proc assignId(node: GrammarNode)
proc nextInTree(node: GrammarNode): HashSet[GrammarNode]
proc isOptional*(node: GrammarNode): bool
proc isGrammarTerminator*(node: GrammarNode): bool 
proc childTerminator(node: GrammarNode): GrammarNode
proc genEpsilonSet(root: GrammarNode)
proc genNextSet(root: GrammarNode)
proc matchToken*(node: GrammarNode, token: Token): bool

let successGrammarNode* = newGrammarNode('s') # sentinel

proc newGrammarNode(name: char, tokenString=""): GrammarNode = 
  case name
  of 'A'..'H', '+', '?', '*':
    result = GrammarNode(kind: name)
  of 'a':
    result = GrammarNode(
      kind: 'a',
      token: strTokenMap[tokenString],
      nextSet: initHashSet[GrammarNode](),
    )
  of 's':  # finish sentinel
    result = GrammarNode(
      kind: 's',
      nextSet: initHashSet[GrammarNode](),
    )
  else:
    raise newException(ValueError, fmt"unknown name: {name}")
  result.epsilonSet = initHashSet[GrammarNode]()


# not to confuse with token terminator
proc isGrammarTerminator(node: GrammarNode): bool =  
  node.kind == 'a' or node.kind == 's'


proc newGrammar(name: string, grammarString: string): Grammar = 
  new result
  result.token = strTokenMap[name]
  result.grammarString = grammarString
  result.rootNode = matchF(result)
  # eliminate non-terminators as root (which happens in cases such as 
  # pass_stmt). The following procedure will be simpler this way
  assert (not result.rootNode.isGrammarTerminator())
  result.cursor = 0
  result.rootNode.assignId
  result.rootNode.genEpsilonSet
  result.rootNode.genNextSet


proc childTerminator(node: GrammarNode): GrammarNode =
  if node.isGrammarTerminator:
    return node
  return childTerminator(node.children[0])

proc nextInTree(node: GrammarNode): HashSet[GrammarNode] = 
  result = initHashSet[GrammarNode]()
  var curNode = node
  while true:
    let father = curNode.father
    if father == nil:
      result.incl(successGrammarNode)
      break
    case father.kind
    of 'F':
      if father.repeat == Repeat.Plus or father.repeat == Repeat.Star:
        result.incl(father)
      curNode = father
    of 'A':
      let idx = father.children.find(curNode)
      assert idx != -1 
      if idx == father.children.len - 1:
        if father.repeat == Repeat.Plus or father.repeat == Repeat.Star:
          result.incl(father)
        curNode = father
      else:
        result.incl(father.children[idx+1])
        break
    else:
      echo curNode
      echo father
      assert false

proc assignId(node: GrammarNode) = 
  var toVisit = initDeque[GrammarNode]()
  toVisit.addLast(node)
  var idx = 1
  while 0 < toVisit.len:
    var node = toVisit.popFirst
    node.id = idx
    inc idx
    if node.isGrammarTerminator:
      continue
    for child in node.children:
      toVisit.addLast(child)


proc genEpsilonSet(root: GrammarNode) = 
  var toVisit = @[root]
  var allNode = initHashSet[GrammarNode]()
  # collect direct epsilon set. Reachable by a single epsilon
  while 0 < toVisit.len:
    let curNode = toVisit.pop
    allNode.incl(curNode)
    case curNode.kind
    of 'F':
      for child in curNode.children:
        curNode.epsilonSet.incl(child)
    of 'A':
      curNode.epsilonSet.incl(curNode.children[0])
      if curNode.isOptional:
        curNode.epsilonSet.incl(curNode.nextInTree)
      for child in curNode.children:
        if child.isOptional:
          child.epsilonSet.incl(child.nextInTree) 
    of 'a':
      discard # no need to do anything
    else:
      echo curNode.kind
      assert false
    if not curNode.isGrammarTerminator:
      for child in curNode.children:
        toVisit.add(child)

  # collect epsilons of member of epsilon set recursively
  var collected = initHashSet[GrammarNode]()
  collected.incl(successGrammarNode)
  for curNode in allNode:
    if not collected.contains(curNode):
      toVisit.add(curNode)
    while 0 < toVisit.len:
      let curNode = toVisit.pop
      if curNode.epsilonSet.len == 0:
        collected.incl(curNode)
        continue
      var allChildrenCollected = true
      for child in curNode.epsilonSet:
        if not collected.contains(child):
          allChildrenCollected = false
          break
      if allChildrenCollected:
        let epsilonSetView = curNode.epsilonSet
        for child in epsilonSetView:
          curNode.epsilonSet.incl(child.epsilonSet)
        collected.incl(curNode)
      else:
        toVisit.add(curNode)
        for child in curNode.epsilonSet:
          if not collected.contains(child):
            toVisit.add(child)

    # exclude 'A' and 'F' in epsilon set
    if curNode.epsilonSet.len == 0:
      continue
    var toExclude = initHashSet[GrammarNode]()
    for child in curNode.epsilonSet:
      case child.kind
      of 'A', 'F':
        toExclude.incl(child)
      else:
        discard
    curNode.epsilonSet.excl(toExclude)

proc genNextSet(root: GrammarNode) = 

  # next set for 'A' and 'F' not accurate. we don't rely on them, use epsilon set instead
  var toVisit: seq[GrammarNode]
  # root.nextSet.incl(successGrammarNode)
  if not root.isGrammarTerminator:
    # toVisit &= root.children
    toVisit.addCompat root.children
  while 0 < toVisit.len:
    let curNode = toVisit.pop
    if not curNode.isGrammarTerminator:
      toVisit &= curNode.children
      continue

    var nextNodes = curNode.nextInTree
    if curNode.repeat == Repeat.Plus or curNode.repeat == Repeat.Star:
      nextNodes.incl(curNode)

    for nextNode in nextNodes:
      for epsilonNextNode in nextNode.epsilonSet:
        curNode.nextSet.incl(epsilonNextNode)
      case nextNode.kind
      of 'A', 'F': # no need to add the node to next set
        continue
      of 'a', 's':  
        curNode.nextSet.incl(nextNode)
      else:
        assert false

proc errorGrammar(grammar: Grammar) =
  let
    s = grammar.grammarString
    c = grammar.cursor

  let msg = fmt"invalid syntax for {s[0..<c]} $${s[c]}$$ {s[c+1..^1]}"
  raise newException(ValueError, msg)


proc hash(node: GrammarNode): Hash = 
  result = hash(addr(node[]))


proc addChild(father, child: GrammarNode) = 
  father.children.add(child)
  child.father = father



  
proc isOptional*(node: GrammarNode): bool = 
  node.repeat == Repeat.Star or node.repeat == Repeat.Query


proc `$`*(grammarNode: GrammarNode): string = 
  if grammarNode == successGrammarNode:
    return "$$SUCCESS_GRAMMAR_NODE$$"
  var stringSeq: seq[string]
  var head = fmt"({grammarNode.id})"
  var tail: string
  case grammarNode.repeat
  of Repeat.None:
    discard
  of Repeat.Star:
    tail = "*"
  of Repeat.Plus:
    tail = "+"
  of Repeat.Query:
    tail = "?"
  let mapProc = proc (n: GrammarNode): string = $n.id
  case grammarNode.kind
  of 'a':
    let nextSet =  sorted(toSeq(grammarNode.nextSet.map(mapProc).items), cmp).join(", ")
    tail &= fmt"<{nextSet}>"
  of 'A', 'F':
    let epsilonSet = sorted(toSeq(grammarNode.epsilonSet.map(mapProc).items), cmp).join(", ")
    tail &= fmt"<{epsilonSet}>"
  else:
    discard
  var name: string
  case grammarNode.kind
  of 'a':
    name = $grammarNode.token
  else:
    name = $grammarNode.kind
  stringSeq.add(head & name & tail)
  if not grammarNode.isGrammarTerminator:
    for child in grammarNode.children:
      if child == nil:
        continue
      for substr in split($(child), "\n"):
        stringSeq.add("    " & substr)
  result = stringSeq.join("\n")


proc `$`*(grammar: Grammar): string =
  result = [$grammar.token & " " & grammar.grammarString, $(grammar.rootNode)].join("\n")


proc getChar(grammar: Grammar): char =
  grammar.cursor.inc grammar.grammarString.skipWhitespace(grammar.cursor)
  result = grammar.grammarString[grammar.cursor]


proc exhausted(grammar: Grammar): bool =
  result = grammar.cursor == len(grammar.grammarString)


proc matchA(grammar: Grammar): GrammarNode = 
  let
    b = matchB(grammar)
    e = matchE(grammar)
    h = matchH(grammar)
  if e != nil:
    case e.kind
    of '+':
      assert b.repeat == Repeat.None
      b.repeat = Repeat.Plus
    of '*':
      assert b.repeat == Repeat.None
      b.repeat = Repeat.Star
    else:
      assert false
  if h != nil:
    result = newGrammarNode('A')
    result.addChild(b)
    if h.repeat != Repeat.None or h.kind == 'F' or h.isGrammarTerminator:
      result.addChild(h)
    else: # basically it's a simple A
      for child in h.children:
        result.addChild(child)
  else:
    result = b
    

proc matchB(grammar: Grammar): GrammarNode = 
  case grammar.getChar()
  of '[':
    result = matchC(grammar)
  of '(':
    result = matchD(grammar)
  of '\'':
    inc(grammar.cursor)
    var prev = grammar.cursor
    grammar.cursor.inc(grammar.grammarString.skipUntil('\'', grammar.cursor))
    inc(grammar.cursor)
    let substr = grammar.grammarString[prev..grammar.cursor-2]
    result = newGrammarNode('a', substr)
  else:
    let first = grammar.cursor
    grammar.cursor.inc(grammar.grammarString.skipWhile(IdentStartChars, grammar.cursor))
    let substr = grammar.grammarString[first..<grammar.cursor]
    result = newGrammarNode('a', substr)


proc matchC(grammar: Grammar): GrammarNode =
  case grammar.getChar
  of '[':
    inc(grammar.cursor)
  else:
    errorGrammar(grammar)
  result = matchF(grammar)
  result.repeat = Repeat.Query
  case grammar.getChar
  of ']':
    inc(grammar.cursor)
  else:
    errorGrammar(grammar)


proc matchD(grammar: Grammar): GrammarNode = 
  case grammar.getChar()
  of '(':
    inc(grammar.cursor)
  else:
    errorGrammar(grammar)
  result = matchF(grammar)
  case grammar.getChar()
  of ')':
    inc(grammar.cursor)
  else:
    errorGrammar(grammar)


proc matchE(grammar: Grammar): GrammarNode = 
  if grammar.exhausted:
    return
  case grammar.getChar()
  of '+': 
    result = newGrammarNode('+')
    inc(grammar.cursor)
  of '*':
    
    result = newGrammarNode('*')
    inc(grammar.cursor)
  else:
    discard


proc matchF(grammar: Grammar): GrammarNode = 
  let a = matchA(grammar)
  let g = matchG(grammar)
  if g != nil:
    result = newGrammarNode('F')
    result.addChild(a)
    for child in g.children:
      result.addChild(child)
  else:
    case a.kind
    of 'a':
      result = newGrammarNode('A')
      result.addChild(a)
    of 'A', 'F':
      result = a
    else:
      echo a.kind
      assert false


proc matchG(grammar: Grammar): GrammarNode = 
  if grammar.exhausted:
    return
  case grammar.getChar
  of '|':
    result = newGrammarNode('G')
    inc(grammar.cursor)
    result.addChild(matchA(grammar))
    let g = matchG(grammar)
    if g != nil:
      for i in g.children:
        result.addChild(i)
  else:
    discard


proc matchH(grammar: Grammar): GrammarNode =
  if grammar.exhausted:
    return
  case grammar.getChar
  of IdentStartChars, '[', '(', '\'': # handcrafted FirstSet for A
    result = matchA(grammar)
  else:
    return


proc lexGrammar = 
  template lines: untyped = grammarLines
  template badGrammar(msg) =
    quitCompat(
      &"lexerGrammer: Unknown syntax at {grammarFilepath}:{lineIdx}:{line}. " &
      msg
    )
  var 
    lineIdx = 0
  while lineIdx < lines.len():
    var line = lines[lineIdx]
    if line.len() < 1 or line[0] == '#':
      inc(lineIdx)
      continue
    let colonIdx = line.find(':')
    if colonIdx == -1:
      badGrammar"expect colon but found none"
    let name = line[0..<colonIdx]

    var
      numPar = 0
      numBra = 0
      startColIdx = colonIdx + 1
      colIdx = startColIdx
      grammarString = ""
    if startColIdx == line.len():
      badGrammar"nothing found after the colon"
    while true:
      while colIdx < line.len():
        # `)(` will lead to bug, assume not gonna happen
        case line[colIdx]
        of '(':
          inc(numPar)
        of ')':
          dec(numPar)
        of '[':
          inc(numBra)
        of ']':
          dec(numBra)
        else:
          discard
        inc(colIdx)
      grammarString &= line[startColIdx..<colIdx]
      if numPar == 0 and numBra == 0:
        break
      else:
        inc(lineIdx)
        line = lines[lineIdx]
        startColIdx = 0
        # skip spaces
        while line[startColIdx] == ' ':
          inc(startColIdx)
        # spare a space
        startColIdx = max(startColIdx - 1, 0)
        colIdx = startColIdx
    inc(lineIdx)
    let grammar = newGrammar(name, grammarString)
    grammarSet[strTokenMap[name]] = grammar


proc genFirstSet(grammar: Grammar) = 
  if grammar.rootNode.kind == 'a':
    let rootToken = grammar.rootNode.token
    if rootToken.isTerminator:
      grammar.firstSet.incl(grammar.rootNode.token)
    else:
      let g = grammarSet[rootToken]
      if not firstSet.hasKey(rootToken):
        g.genFirstSet
      grammar.firstSet.incl(g.firstSet)
    return
  for firstNode in grammar.rootNode.epsilonSet:
    if firstNode.token.isNonTerminator: # this is a grammar token
      let firstGrammar = grammarSet[firstNode.token]
      if firstGrammar.firstSet.card == 0:
        firstGrammar.genFirstSet
      grammar.firstSet.incl(firstGrammar.firstSet)
    else:
      grammar.firstSet.incl(firstNode.token)



proc genFirstSet = 
  for grammar in grammarSet.values:
    if firstSet.hasKey(grammar.token):
      continue
    grammar.genFirstSet


proc validateFirstSet = 
  proc detectConflict(nodes: HashSet[GrammarNode]): bool = 
    var accumulate: set[Token]
    for node in nodes:
      if node.kind == 's':
        continue
      assert node.kind == 'a'
      var newTokens: set[Token]
      if node.token.isTerminator:
        newTokens.incl(node.token)
      else:
        newTokens.incl(grammarSet[node.token].firstSet)
      if (accumulate * newTokens).card == 0:
        accumulate.incl(newTokens)
      else:
        return true
    false

  for grammar in grammarSet.values:
    if grammar.rootNode.kind == 'a': # conflict not possible
      continue
    if grammar.rootNode.epsilonSet.detectConflict: # conflict for root node
      echo grammar
    var toVisit = @[grammar.rootNode]
    while 0 < toVisit.len:
      let curNode = toVisit.pop
      if not curNode.isGrammarTerminator:
        for child in curNode.children:
          toVisit.add(child)
      if curNode.kind == 'a':
        if curNode.nextSet.detectConflict:
          echo grammar.token
          echo curNode

proc matchToken(node: GrammarNode, token: Token): bool = 
  if node.token.isTerminator:
    if node == successGrammarNode:
      return true # assume it's done and leave the problem to the upper level
    else:
      return node.token == token
  else:
    return token in grammarSet[node.token].firstSet

lexGrammar()

genFirstSet()


when isMainModule:
  validateFirstSet()
  for grammar in grammarSet.values:
    echo grammar
    echo "### " & toSeq(grammar.firstSet.items).join(" ")

  

