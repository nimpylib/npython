
import token
import ../Utils/[utils]

#const MAXFSTRINGLEVEL = 150  ## Max f-string nesting level
type
  Mode* {.pure.} = enum
    Single = "single"
    File = "exec"
    Eval = "eval"
  #[
  LexerState* = enum
    E_OK = 10
    E_EOF = 11
    E_DONE = 16
    E_TABSPACE = (18, "Inconsistent mixing of tabs and spaces")
    E_LINECONT = (25, "Unexpected characters after a line continuation")
    E_EOFS = (23, "EOF in triple-quoted string")
  ]#
  tokenizer_mode_kind_t* = enum
    TOK_REGULAR_MODE
    TOK_FSTRING_MODE    
  string_kind_t*{.pure.} = enum
    FSTRING
    TSTRING
  tokenizer_mode* = object
    kind*: tokenizer_mode_kind_t

    quote*: char
    quote_size*: int
    raw*: bool

    curly_bracket_depth*,
      curly_bracket_expr_start_depth*: int
    start*, multi_line_start*: int
    first_line*: int

    start_offset*,
      multi_line_start_offset*: int

    last_expr_size*,
      last_expr_end*: int
    # char* last_expr_buffer;
    when not defined(release):
      in_debug*: bool
    # int in_format_spec;

    string_kind: string_kind_t

  LexerEscaper* = proc (s: string): string{.raises: [SyntaxError].}
  Lexer* = ref object
    ## For CPython 3.13, this is roughly equal to `tok_state*`
    indentStack: seq[int] # Stack to track indentation levels
    lineNo: int
    tokenNodes*: seq[TokenNode] # might be consumed by parser
    fileName*: string
    metContChar*: bool  ## whether is after the line
    ## whose last token was a line continuation character '\'
    parenLevel*: int # nesting level for (, [ and { to support implicit continuation

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
    tok_mode_stack*: seq[tokenizer_mode] #= @[tokenizer_mode()] # array[MAXFSTRINGLEVEL, tokenizer_mode]

using lexer: Lexer
{.push inline.}
proc getMode*(lexer): var tokenizer_mode = lexer.tok_mode_stack[^1]  ## TOK_GET_MODE
proc new_tokenizer_mode: tokenizer_mode{.inline.} = discard
proc asNextMode(lexer; m: tokenizer_mode) =
  ## TOK_NEXT_MODE
  #result = tokenizer_mode()
  lexer.tok_mode_stack.add m
proc popMode*(lexer): tokenizer_mode =
  lexer.tok_mode_stack.pop
{.pop.}
template withNextMode*(lexer; it; doWithIt) =
  bind new_tokenizer_mode, asNextMode
  block:
    var it{.inject.} = new_tokenizer_mode()
    doWithIt
    lexer.asNextMode it
template withNextMode*(lexer; doWithIt) =
  withNextMode(lexer, it, doWithIt)


template INSIDE_FSTRING*(lexer: Lexer): bool = lexer.tok_mode_stack.len > 0
template INSIDE_FSTRING_EXPR*(tok: tokenizer_mode): bool = tok.curly_bracket_expr_start_depth >= 0
template INSIDE_FSTRING_EXPR_AT_TOP*(tok: tokenizer_mode): bool =
    (tok.curly_bracket_depth - tok.curly_bracket_expr_start_depth == 1)


proc parseModeEnum*(s: string, res: var Mode): bool =
  template ret(x) =
    res = Mode.x
    return true
  case s
  of "single": ret Single
  of "exec": ret File
  of "eval": ret Eval
  else: return false

proc cont*(lexer: Lexer): bool{.inline.} = lexer.metContChar or lexer.tripleStr.within or lexer.parenLevel > 0

proc lineNo*(lexer: Lexer): var int{.inline.} = lexer.lineNo

proc indentStack*(lexer: Lexer): var seq[int]{.inline.} = lexer.indentStack
