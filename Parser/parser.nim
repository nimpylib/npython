import strformat

import strutils
import sequtils
import sets
import tables

import grammar
import lexer
import token
import ../Utils/utils

type

  ParseStatus {.pure.} = enum
    Normal
    Finished
    Error

  ParseNode* = ref object
    tokenNode*: TokenNode
    children*: seq[ParseNode] # children in the CST
    grammarNodeSeq: seq[GrammarNode]  # current state in NFA


proc newParseNode(tokenNode: TokenNode): ParseNode = 
  assert tokenNode.token.isTerminator
  new result
  result.tokenNode = tokenNode


proc newParseNode(tokenNode, firstToken: TokenNode): ParseNode =
  assert (firstToken.token in grammarSet[tokenNode.token].firstSet)
  new result
  result.tokenNode = tokenNode
  let gNode = grammarSet[tokenNode.token].rootNode
  var toAdd: ParseNode
  for child in gNode.epsilonSet:
    if child.matchToken(firstToken.token):
      result.grammarNodeSeq.add(child)
      if child.token.isTerminator:
        if toAdd.isNil:
          toAdd = newParseNode(firstToken)
        else:
          assert toAdd.tokenNode.token == child.token
      else:
        if toAdd.isNil:
          toAdd = newParseNode(newTokenNode(child.token), firstToken)
        else:
          assert toAdd.tokenNode.token == child.token
  assert (not toAdd.isNil)
  result.children.add(toAdd)

proc `$`*(node: ParseNode): string = 
  if node.children.len == 0:
    return fmt"{node.tokenNode}"
  var stringSeq = @[$node.tokenNode]
  for child in node.children:
    stringSeq.add split($(child), "\n").mapIt("    " & it).join("\n")
  return stringSeq.join("\n")

proc finished*(node: ParseNode): bool = 
  var nonTerminatorTokenAppeared = false
  for gn in node.grammarNodeSeq:
    if not (successGrammarNode in gn.nextSet):
      return false
    if not nonTerminatorTokenAppeared and not gn.token.isTerminator:
      nonTerminatorTokenAppeared = true
      if not node.children[^1].finished:
        return false
  return true

# simulate NFA directly
proc applyToken(node: ParseNode, token: TokenNode): ParseStatus =  
  var gNodeSeq = node.grammarNodeSeq
  var newGnSeq : seq[GrammarNode]
  var thisLayer = false # ensures at most one parse node is added to node.children
  proc addNexts(gn: GrammarNode) = 
    for nextGn in gn.nextSet:
      if nextGn.matchToken(token.token):
        newGnSeq.add(nextGn)
        if nextGn == successGrammarNode:  
          continue  # no need to worry about adding child
        if thisLayer:
          # make sure they are the same token, otherwise beyond LL1
          assert node.children[^1].tokenNode.token == nextGn.token
        else:
          thisLayer = true
          if nextGn.token.isTerminator:
            node.children.add(newParseNode(token))
          else:
            node.children.add(newParseNode(newTokenNode(nextGn.token), token))
  # flags to make sure dive into child once for non-terminators
  var nonTerminatorTokenAppeared = false 
  var childStatus: ParseStatus   
  for gn in gNodeSeq:
    case gn.kind
    of 'a':
      if gn.token.isTerminator:
        addNexts(gn)
      else:
        if not nonTerminatorTokenAppeared: # only process once for non terminator
          childStatus = node.children[^1].applyToken(token)
          nonTerminatorTokenAppeared = true
        case childStatus
        of ParseStatus.Normal:
          newGnSeq.add(gn) # enter this grammar node in the next parsing
        of ParseStatus.Error: # do nothing, remove this grammar node
          discard
        of ParseStatus.Finished: # the child is unable to process this token
          addNexts(gn)
    of 's':
      discard # discard the previous success indeed..
    else:
      let msg = fmt"Grammar Node of {gn} has kind {gn.kind}"
      echo msg
      assert false

  if newGnSeq.len == 0:
    return ParseStatus.Error
  else:
    node.grammarNodeSeq = newGnSeq

  if node.grammarNodeSeq.len == 1 and node.grammarNodeSeq[0] == successGrammarNode:
    ParseStatus.Finished
  else:
    ParseStatus.Normal


proc parseWithState*(input: string, 
                     lexer: Lexer,
                     mode=Mode.File, 
                     parseNodeArg: ParseNode = nil,
                     ): ParseNode = 

  ## like `_PyPegen_run_parser_from_string` or
  ##      `_PyPegen_run_parser(Parser *p)` in Python 3.13
  lexer.lexString(input, mode)
  try:
    var tokenSeq = lexer.tokenNodes
    if tokenSeq.len == 0:
      return
    var parseNode: ParseNode
    var start = 0
    
    if parseNodeArg.isNil:
      # construct a cst using the first token
      let firstToken = tokenSeq[0]
      start = 1
      var rootToken: Token
      case mode
      of Mode.Single:
        rootToken = Token.single_input
      of Mode.File:
        rootToken = Token.file_input
      of Mode.Eval:
        rootToken = Token.eval_input
      if not (firstToken.token in grammarSet[rootToken].firstSet):
        raiseSyntaxError("SyntaxError", "", firstToken.lineNo, firstToken.colNo)
      parseNode = newParseNode(newTokenNode(rootToken), firstToken)
    else:
      parseNode = parseNodeArg
    for token in tokenSeq[start..^1]:
      let status = parseNode.applyToken(token)
      when defined(debug):
        echo fmt"{status}, {token}"
      case status
      of ParseStatus.Normal:
        continue
      else:
        raiseSyntaxError("SyntaxError", "", token.lineNo, token.colNo)
    parseNode
  finally:
    # so that we won't process the same tokens again
    lexer.clearTokens()
  
proc parse*(input: string, fileName: string, mode=Mode.File): ParseNode = 
  let lexer = newLexer(fileName)
  parseWithState(input, lexer, mode)
