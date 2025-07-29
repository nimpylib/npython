import macros
import sequtils
import strformat
import sets
import tables
from strutils import splitLines
from parseutils import parseUntil, skipUntil


const
  grammarFileName = "Grammar"

  basicToken = @[
              ("ENDMARKER" , "Endmarker"),
              ("NAME"      , "Name"),
              ("NUMBER"    , "Number"),
              ("BYTES"    ,  "Bytes"),
              ("STRING"    , "String"),
              ("NEWLINE"   , "Newline"),
              ("INDENT"    , "Indent"),
              ("DEDENT"    , "Dedent"),
              ("("         , "Lpar"),
              (")"         , "Rpar"),
              ("["         , "Lsqb"),
              ("]"         , "Rsqb"),
              (":"         , "Colon"),
              (","         , "Comma"),
              (";"         , "Semi"),
              ("+"         , "Plus"),
              ("-"         , "Minus"),
              ("*"         , "Star"),
              ("/"         , "Slash"),
              ("|"         , "Vbar"),
              ("&"         , "Amper"),
              ("<"         , "Less"),
              (">"         , "Greater"),
              ("="         , "Equal"),
              ("."         , "Dot"),
              ("%"         , "Percent"),
              ("{"         , "Lbrace"),
              ("}"         , "Rbrace"),
              ("=="        , "Eqequal"),
              ("!="        , "Notequal"),
              ("<="        , "Lessequal"),
              (">="        , "Greaterequal"),
              ("~"         , "Tilde"),
              ("^"         , "Circumflex"),
              ("<<"        , "Leftshift"),
              (">>"        , "Rightshift"),
              ("**"        , "Doublestar"),
              ("+="        , "Plusequal"),
              ("-="        , "Minequal"),
              ("*="        , "Starequal"),
              ("/="        , "Slashequal"),
              ("%="        , "Percentequal"),
              ("&="        , "Amperequal"),
              ("|="        , "Vbarequal"),
              ("^="        , "Circumflexequal"),
              ("<<="       , "Leftshiftequal"),
              (">>="       , "Rightshiftequal"),
              ("**="       , "Doublestarequal"),
              ("//"        , "Doubleslash"),
              ("//="       , "Doubleslashequal"),
              ("@"         , "At"),
              ("@="        , "Atequal"),
              ("->"        , "Rarrow"),
              ("..."       , "Ellipsis"),
              ("<>"        , "PEP401"),
  ]


proc readGrammarToken: seq[string] {.compileTime.} = 
  var textLines = slurp(grammarFileName).splitLines()
  for line in textLines:
    if line.len == 0:
      continue
    if line[0] in 'a'..'z':
      var tokenString: string
      discard line.parseUntil(tokenString, ':') # stored in tokenString
      result.add(tokenString)


# everything inside pars
proc readReserveName: HashSet[string] {.compileTime.} = 
  let text = slurp(grammarFileName)
  result = initHashSet[string]()
  var idx = 0
  while idx < text.len:
    case text[idx]
    of '\'':
      inc idx
      let l = text.skipUntil('\'', idx)
      result.incl(text[idx..<idx+l])
      idx.inc(l+1)
    of '#':
      idx.inc(text.skipUntil('\n', idx))
      inc idx
    else:
      inc idx
   
  for t in basicToken:
    result.excl(t[0])

const grammarTokenList* = readGrammarToken()


const reserveNameSet* = readReserveName()


macro genTokenType(tokenTypeName, boundaryName: untyped): untyped = 
  result = newStmtList()
  var enumFields: seq[NimNode]
  enumFields.add(ident("NULLTOKEN"))
  for t in basicToken:
    enumFields.add(ident(t[1]))
  for t in reserveNameSet:
    enumFields.add(ident(t))
  enumFields.add(boundaryName)
  for t in grammarTokenList:
    enumFields.add(ident(t))
  result.add(newEnum(
    name = tokenTypeName,
    fields = enumFields,
    public = true,
    pure = true
  ))


genTokenType(Token, boundary)


proc isTerminator*(node: Token): bool = 
  node < Token.boundary

proc isNonTerminator*(node: Token): bool = 
  Token.boundary < node

macro genMapTable(tokenTypeName, tableName: untyped): untyped = 
  result = newStmtList()
  let tableNode = nnkTableConstr.newTree()
  for t in basicToken:
    let tokenNode = newDotExpr(tokenTypeName, ident(t[1]))
    tableNode.add(newColonExpr(newStrLitNode(t[0]), tokenNode))
  for t in grammarTokenList & toSeq(reserveNameSet.items):
    let tokenNode = newDotExpr(tokenTypeName, ident(t))
    tableNode.add(newColonExpr(newStrLitNode(t), tokenNode))
    
  let dotNode = newDotExpr(tableNode, newIdentNode("newTable"))
  let letStmt = newLetStmt(tableName.postFix("*"), dotNode)
  result.add(letStmt)


genMapTable(Token, strTokenMap)

proc genTerminatorSet: set[Token] {. compileTime .} = 
  for token in Token:
    if token.isTerminator:
      result.incl token

const terminatorSet = genTerminatorSet()

# token nodes that should have a content field
const contentTokenSet* = {Token.Name, Token.Number, Token.String, Token.Bytes}

type
  TokenNode* = ref object
    case token*: Token
    of terminatorSet:
      lineNo*: int
      colNo*: int
      content*: string # only for name, number, bytes, and string
    else:
      discard

proc `$`*(node: TokenNode): string = 
  case node.token
  of contentTokenSet:
    fmt"<{node.token}> {node.content}"
  else:
    fmt"<{node.token}>"

when isMainModule:
  echo grammarTokenList
  echo reserveNameSet
  echo strTokenMap
