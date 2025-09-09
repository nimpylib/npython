
import token
import ../Utils/[utils]

type
  Mode* {.pure.} = enum
    Single
    File
    Eval
  #[
  LexerState* = enum
    E_OK = 10
    E_EOF = 11
    E_DONE = 16
    E_TABSPACE = (18, "Inconsistent mixing of tabs and spaces")
    E_LINECONT = (25, "Unexpected characters after a line continuation")
    E_EOFS = (23, "EOF in triple-quoted string")
  ]#
  LexerEscaper* = proc (s: string): string{.raises: [SyntaxError].}
  Lexer* = ref object
    ## For CPython 3.13, this is roughly equal to `tok_state*`
    indentStack: seq[int] # Stack to track indentation levels
    lineNo: int
    tokenNodes*: seq[TokenNode] # might be consumed by parser
    fileName*: string

    tripleStr*: tuple[
      within: bool,
      val: string,
      quote: char, # ' or "
      tokenKind: Token,  # String or Bytes
      escape: LexerEscaper,
      start: tuple[
        lineNo, colNo: int,
      ]
    ]  ## is handling triple string (multiline string)



proc cont*(lexer: Lexer): bool{.inline.} = lexer.tripleStr.within

proc lineNo*(lexer: Lexer): var int{.inline.} = lexer.lineNo

proc indentStack*(lexer: Lexer): var seq[int]{.inline.} = lexer.indentStack
