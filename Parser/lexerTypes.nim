
import token

type
  Mode* {.pure.} = enum
    Single
    File
    Eval

  Lexer* = ref object
    ## For CPython 3.13, this is roughly equal to `tok_state*`
    indentStack: seq[int] # Stack to track indentation levels
    lineNo: int
    tokenNodes*: seq[TokenNode] # might be consumed by parser
    fileName*: string

proc lineNo*(lexer: Lexer): var int{.inline.} = lexer.lineNo

proc indentStack*(lexer: Lexer): var seq[int]{.inline.} = lexer.indentStack
