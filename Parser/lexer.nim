import ./lexer_utils
import deques
import sets
import strformat
import strutils
import typetraits
import tables
import parseutils

import token
import ./string_parser
import ./lexerTypes
export lexerTypes except lineNo, indentStack
import ../Utils/[utils, compat]

type
  # save source file for traceback info
  Source = ref object
    lines: seq[string]

const
  BPrefix = {'b', 'B'}
  RPrefix = {'r', 'R'}
  FPrefix = {'f', 'F'}
  TPrefix = {'t', 'T'}
  StrLitPrefix = BPrefix + RPrefix + FPrefix + TPrefix + {'u', 'U'}
  StrLitQuote = {'"', '\''}

template indentLevel(lexer: Lexer): int = lexer.indentStack[^1]

var sourceFiles = initTable[string, Source]()

proc addSource*(filePath, content: string) = 
  let s = sourceFiles.mgetOrPut(filePath, new Source)
  # s.lines.add content.split("\n")
  s.lines.addCompat content.split("\n")

type
  GetSourceRes* = enum
    GSR_Success
    GSR_NoSuchFile
    GSR_LineNoNotSet
    GSR_LineNoOutOfRange

proc getSource*(filePath: string, lineNo: int; res: var string): GetSourceRes =
  # lineNo starts from 1!
  if lineNo == 0:
    return GSR_LineNoNotSet
  sourceFiles.withValue filePath, value:
    if lineNo > value.lines.len or lineNo < 1:
      res = $value.lines.len
      return GSR_LineNoOutOfRange
    res = value.lines[lineNo-1]
    return GSR_Success
  do:
    return GSR_NoSuchFile

proc `$`*(lexer: Lexer): string = 
  $lexer.tokenNodes


# used in parser.nim to construct non-terminators
proc newTokenNode*(token: Token, 
                   lineNo = -1, colNo = -1,
                   content = ""): TokenNode = 
  new result
  if token == Token.Name and content in reserveNameSet: 
    try:
      result = TokenNode(token: strTokenMap[content])
    except KeyError:
      unreachable
  else:
    case token
    of contentTokenSet:
      result = TokenNode(token: token, content: content)
    else:
      assert content == ""
      result = TokenNode(token: token)
  assert result.token != Token.NULLTOKEN
  if result.token.isTerminator:
    assert -1 < lineNo and -1 < colNo
    result.lineNo = lineNo
    result.colNo = colNo
  else:
    assert lineNo < 0 and colNo < 0


proc newLexer*(fileName: string): Lexer = 
  new result
  result.fileName = fileName
  result.indentStack = @[0] # Start with a single zero on the stack
proc newLexer*(fileName: string, lineNo: int): Lexer = 
  result = newLexer(fileName)
  result.lineNo = lineNo

# when we need a fresh start in interactive mode
proc clearTokens*(lexer: Lexer) = 
  # notnull checking issue for the compiler. gh-10651
  if lexer.tokenNodes.len != 0:
    lexer.tokenNodes.setLen 0

proc clearIndent*(lexer: Lexer) = 
  lexer.indentLevel = 0

proc add(lexer: Lexer, token: TokenNode) = 
  lexer.tokenNodes.add(token)

proc add(lexer: Lexer, token: Token, colNo:int) = 
  assert token.isTerminator
  lexer.add(newTokenNode(token, lexer.lineNo, colNo))

template delLast(s: seq) =
  discard s.pop()

# At the end of the file, generate DEDENT tokens for remaining stack levels
proc dedentAll*(lexer: Lexer) = 
  while lexer.indentStack.len > 1:
    lexer.indentStack.delLast()
    lexer.add(Token.Dedent, lexer.indentStack[^1])
    #dec lexer.indentLevel

proc eatTripleQuote(line: openArray[char], idx: var int, pairingChar: char): bool =
  assert line[idx] == pairingChar
  template isPairOff(offset): bool = line[idx+offset] == pairingChar
  result = idx+2 < line.len and
    # ''' or """
    #[0.isPairOff and ]#1.isPairOff and 2.isPairOff
  if result: idx.inc 3

proc feedTripleStrContent(lexer: Lexer, line: string, idx: var int): TokenNode =
  assert lexer.tripleStr.within

  let last = idx + line.skipUntil(lexer.tripleStr.quote, idx)
  let start = idx
  template pushTill(i) =
    let s = lexer.tripleStr.escape(line[start..<i])
    lexer.tripleStr.val.add s
  if last != line.len:
    if (idx=last; eatTripleQuote(line, idx, lexer.tripleStr.quote)):
      # if found ending triple quote in the same line
      pushTill last
      result = newTokenNode(
        lexer.tripleStr.tokenKind,
        lexer.tripleStr.start.lineNo,
        lexer.tripleStr.start.colNo,
        lexer.tripleStr.val)
      lexer.tripleStr.within = false
      lexer.tripleStr.val.setLen 0
      return
  else:
    # still within triple string
    result = nil
    if line[last-1] == '\\':
      # if ended with a line continuation character `\`
      #[ in Python, """xxx\
""" -> "xxx"
      ]#
      pushTill last - 1
      idx = last
      return

  # is a normal string content within triple string
  pushTill line.len
  idx = line.len
  lexer.tripleStr.val.add '\n'  # all newline in triple string are normalized to NL

proc lexOneLine(lexer: Lexer, line: string, mode: Mode) {.inline, raises: [SyntaxError].} 

template raiseSyntaxError(msg: string) = 
  # fileName set elsewhere
  raiseSyntaxError(msg, lexer.fileName, lexer.lineNo, idx)

template getStr(str): TokenNode =
  newTokenNode(Token.FStringMiddle, lexer.lineNo, idx,
    if the_current_tok.raw: str else: lexer.decode_unicode_with_escapes str)
template retStr(str) =
  return getStr(str)

const
  LBrace = '{'
  RBrace = '}'

template TODO_multi_fstring =
  unreachable "not impl multi-line f-string"  #TODO:fstring

template lexFStringMiddleTmpl(lexer: Lexer, line: string, idx: var int, the_current_tok: tokenizer_mode; doOnL, doOnR; doOnEndLR) =
  var s{.inject.}: string
  #let quote = the_current_tok.quote

  template handleDupBraceOr(brace; elseDo) =
    if idx != line.high:
      if line[idx+1] == brace:
        s.add brace
        idx.inc 2
        continue
      else:
        elseDo
    else:
      # string till end, and endswith '{' or '}'
      doOnEndLR

  let L = line.len
  while idx < L:
    let c{.inject.} = line[idx]
    case c
    of LBrace:
      handleDupBraceOr LBrace:
        # start `{ ... }`
        doOnL
    of RBrace:
      handleDupBraceOr RBrace:
        # `xxx}xxx`
        doOnR
    of '\'', '"':
      if the_current_tok.quote == c:
        if not the_current_tok.raw:
          if idx == 0: unreachable
          if line[idx-1] == '\\':
            s.add c
            continue
        if the_current_tok.quote_size == 1:
          # DO NOT idx.inc here, as we need quote to emit End in next cycle
          break
        else:
          assert the_current_tok.quote_size == 3
          TODOmulti_fstring
    else:
      s.add c
    idx.inc
  retStr s


template newTokenNodeWithNo(Tk): TokenNode = 
    newTokenNode(Token.Tk, lexer.lineNo, idx)

proc lexFStringMiddle(lexer: Lexer, line: string, idx: var int, the_current_tok: tokenizer_mode): TokenNode =
  lexer.lexFStringMiddleTmpl(line, idx, the_current_tok):

      lexer.withNextMode:
        it.curly_bracket_expr_start_depth.inc
        assert line[idx] == LBrace
        it.start = idx+1
      lexer.add getStr s
      idx.inc
      lexer.add newTokenNodeWithNo(Lbrace)
      return
  do:
      raiseSyntaxError "f-string: single '}' is not allowed"
  do: retStr line

proc getNextTokenImpl(
  lexer: Lexer, 
  line: string, 
  idx: var int, mode: Mode, fstring_mode: static[bool] = false): TokenNode {. raises: [SyntaxError] .}

proc lexFStringInExpr(lexer: Lexer, line: string, idx: var int, the_current_tok: tokenizer_mode, mode: Mode): TokenNode =
  ## lex f-string expression before the closing '}'
  template tryCloseExpr =
      lexer.getMode().curly_bracket_depth.dec
      lexer.getMode().curly_bracket_expr_start_depth.dec
      if INSIDE_FSTRING_EXPR(lexer.getMode()):
        assert line[idx] == RBrace
        let cur_tok_mode = lexer.popMode()

        var idx_in_expr = cur_tok_mode.start

        let lastIdx = idx - 1

        # If there's a top-level ':' before the closing '}', split the
        # f-string replacement field into expression and format-spec parts.
        var colonPosNext = -1
        var paren = 0
        var bracket = 0
        var braceCnt = 0

        while idx_in_expr < idx:
          #TODO:fstring: lambda
          let ntok = lexer.getNextTokenImpl(line, idx_in_expr, mode, fstring_mode = true)
          lexer.add ntok

          case ntok.token
          of Lpar: paren.inc
          of Rpar: paren.dec
          of Lsqb: bracket.inc
          of Rsqb: bracket.dec
          of Token.Lbrace: braceCnt.inc
          of Token.Rbrace: braceCnt.dec
          of Colon:
            if paren == 0 and bracket == 0 and braceCnt == 0:
              colonPosNext = idx_in_expr
              break
          of lambda:
            if paren == 0 and bracket == 0 and braceCnt == 0:
              raiseSyntaxError "f-string: lambda expressions are not allowed without parentheses"
          else: discard

        if colonPosNext >= 0:
          # the rest until the closing brace is a format-spec (FSTRING_MIDDLE)
          let fmtStart = colonPosNext
          if fmtStart <= lastIdx:
            let content = line[fmtStart .. lastIdx]
            lexer.add(newTokenNode(Token.FStringMiddle, lexer.lineNo, fmtStart, content))
            #TODO:fstring:fstring_format_spec: FSTRING_MIDDLE | fstring_replacement_field

        if colonPosNext >= 0:
          # the rest until the closing brace is a format-spec (FSTRING_MIDDLE)
          let fmtStart = colonPosNext
          if fmtStart <= lastIdx:
            let content = line[fmtStart .. lastIdx]
            lexer.add(newTokenNode(Token.FStringMiddle, lexer.lineNo, fmtStart, content))
            #TODO:fstring:fstring_format_spec: FSTRING_MIDDLE | fstring_replacement_field
        return

  lexer.lexFStringMiddleTmpl(line, idx, the_current_tok):
      lexer.getMode().curly_bracket_depth.inc
      s.add c
  do:
      tryCloseExpr
      raiseSyntaxError "f-string: single '}' is not allowed"
  do:
    if c == LBrace:
      raiseSyntaxError "f-string: expecting '}'"
    else: tryCloseExpr

proc getNextToken(
  lexer: Lexer, 
  line: string, 
  idx: var int, mode: Mode): TokenNode {. raises: [SyntaxError] .} =
  if INSIDE_FSTRING(lexer):
    let the_current_tok = lexer.getMode()
    if INSIDE_FSTRING_EXPR(the_current_tok):
      return lexer.lexFStringInExpr(line, idx, the_current_tok, mode)
      #return lexer.getNextTokenImpl(line, idx, mode, fstring_mode = true)
    else:
      # string literal
      let cur = line[idx]
      case cur
      of RBrace:
        idx.inc
        return newTokenNodeWithNo(Rbrace)
      elif cur == the_current_tok.quote:
        if the_current_tok.quote_size == 1:
          idx.inc
          discard lexer.popMode()
          return newTokenNodeWithNo(FStringEnd)
        else:
          TODO_multi_fstring
      else:
        return lexer.lexFStringMiddle(line, idx, the_current_tok)
  lexer.getNextTokenImpl(line, idx, mode)

# the function can probably be generated by a macro...
proc getNextTokenImpl(
  lexer: Lexer, 
  line: string, 
  idx: var int, mode: Mode, fstring_mode: static[bool] = false): TokenNode {. raises: [SyntaxError] .} = 
  ## if continuious line is required, return nil
  ## 
  ## Current for f-string's expression, it also returns nil but store tokens in `lexer`
  if lexer.tripleStr.within:
    return lexer.feedTripleStrContent(line, idx)

  template addToken(tokenName) =
    var content: string
    let first = idx
    var msg: string
    if not `parse tokenName`(line, content, idx=idx, msg=msg):
      raiseSyntaxError(msg, lexer.fileName, lineNo=lexer.lineNo, colNo=idx)
    result = newTokenNode(Token.tokenName, lexer.lineNo, first, content)

  template addSingleCharToken(tokenName) = 
    result = newTokenNode(Token.tokenName, lexer.lineNo, idx)
    inc idx

  template tailing(t: char): bool = 
    (idx < line.len - 1) and line[idx+1] == t

  template addSingleOrDoubleCharToken(tokenName1, tokenName2: untyped, c:char) = 
    if tailing(c):
      result = newTokenNode(Token.tokenName2, lexer.lineNo, idx)
      idx += 2
    else:
      addSingleCharToken(tokenName1)


  template addId =
    addToken(Name)

  template asIs(x): untyped = x  
  template addStringImpl(pairingChar: char, isRaw: bool, escaper: untyped, tok=Token.String) =
    ## PY-DIFF: We use different Token for bytes and str, for s as a String/Bytes Token,
    ##  `s` is translated content (e.g. `r'\n'` translated to Newline Char),
    ##  unlike CPython only has String Token and `s[0]` is prefix and `s[1]` is quotation mark, as it's no need to check again
    if eatTripleQuote(line, idx, pairingChar):
      lexer.tripleStr.quote = pairingChar
      lexer.tripleStr.within = true
      lexer.tripleStr.tokenKind = tok
      lexer.tripleStr.escape = (proc(s: string): string = escaper(s))
      lexer.tripleStr.start = (lexer.lineNo, idx)
      return lexer.feedTripleStrContent(line, idx)
    idx.inc
    var last = idx
    while true:
      last += line.skipUntil(pairingChar, last)
      if last == line.len: # pairing `"` not found
        raiseSyntaxError("Invalid string syntax")
      else:
        when isRaw: break
        else:
          if line[last-1] == '\\':
            last.inc  # avoid treating \' or \" as ending quote
          else:
            break
    let s = escaper(line[idx..<last])
    result = newTokenNode(tok, lexer.lineNo, idx, s)
    idx = last
    idx.inc  # skip ending pairingChar

  template addString(pairingChar: char, tok=Token.String) =
    addStringImpl(pairingChar, false,
      lexer.decode_unicode_with_escapes,
      tok)
  template addRawString(pairingChar: char, tok=Token.String) =
    addStringImpl(pairingChar, true, asIs, tok)


  template startFString(strkind: string_kind_t, traw: bool) =
    var quote_size = 1
    if eatTripleQuote(line, idx, quote):
      quote_size = 3
    else:
      idx.inc
    lexer.withNextMode:
      it.kind = TOK_FSTRING_MODE
      it.quote = quote
      it.quote_size = quote_size
      it.start = idx
      it.multi_line_start = idx #FIXME
      it.first_line = lexer.lineNo
      it.start_offset = -1
      it.multi_line_start_offset = -1

      it.last_expr_end = -1

      it.raw = traw

      it.string_kind = strkind
      it.curly_bracket_depth = 0
      it.curly_bracket_expr_start_depth = -1

    result = if (strkind == string_kind_t.FSTRING): newTokenNodeWithNo FStringStart
      else: newTokenNodeWithNo TStringStart

  while true: # Only for empty between tokens
    let curChar = line[idx]
    case curChar
    of Whitespace - Newlines:  # empty between tokens, like `1 + 2` 
      inc idx
      continue
    of '#': # Comment line
      break

    # the following will be executed just once (not to be in loop)
    of {'a'..'z', 'A'..'Z', '_'} - StrLitPrefix:
      addId
    of StrLitPrefix:
      let prefix = curChar
      var quote: char
      template nextIsQuote(i=idx): bool =
        i < line.high and (quote = line[i+1]; quote) in StrLitQuote
      if nextIsQuote():
        idx += 1
        case prefix
        of BPrefix: addString quote, Token.Bytes
        of RPrefix: addRawString quote
        of FPrefix:
          startFString FSTRING, false
        else: addString quote
      else:
        block ChkPrefix:
          template chk(additionSet; doSth) =
            if (
              prefix in additionSet and quote in RPrefix or
              quote in additionSet and prefix in RPrefix
            ) and (nextIsQuote(idx+1)): # raw bytes: br, bR, rb, etc.
              idx += 2
              doSth
              break ChkPrefix
          chk BPrefix:
            addRawString quote, Token.Bytes
          
          chk FPrefix:
            startFString FSTRING, true
          addId
    of '0'..'9':
      addToken(Number)
    of StrLitQuote:
      if idx == line.len - 1:
        raiseSyntaxError("Invalid string syntax")
      addString curChar

    of '\n':
      result = newTokenNodeWithNo(Newline)
      idx += 1
    of '(':
      addSingleCharToken(Lpar)
    of ')':
      addSingleCharToken(Rpar)
    of '[':
      addSingleCharToken(Lsqb)
    of ']':
      addSingleCharToken(Rsqb)
    of ':':
      addSingleCharToken(Colon)
    of ',':
      addSingleCharToken(Comma)
    of ';':
      addSingleCharToken(Semi)
    of '+': 
      addSingleOrDoubleCharToken(Plus, PlusEqual, '=')
    of '-':
      if tailing('='):
        result = newTokenNodeWithNo(MinEqual)
        idx += 2
      elif tailing('>'):
        result = newTokenNodeWithNo(Rarrow)
        idx += 2
      else:
        addSingleCharToken(Minus)
    of '*':
      if tailing('*'):
        inc idx
        if tailing('='):
          result = newTokenNodeWithNo(DoubleStarEqual)
          idx += 2
        else:
          result = newTokenNodeWithNo(DoubleStar)
          inc idx
      else:
        addSingleOrDoubleCharToken(Star, StarEqual, '=')
    of '/':
      if tailing('/'):
        inc idx
        if tailing('='):
          result = newTokenNodeWithNo(DoubleSlashEqual)
          idx += 2
        else:
          result = newTokenNodeWithNo(DoubleSlash)
          inc idx
      else:
        addSingleOrDoubleCharToken(Slash, SlashEqual, '=')
    of '|':
      addSingleOrDoubleCharToken(Vbar, VbarEqual, '=')
    of '&':
      addSingleOrDoubleCharToken(Amper, AmperEqual, '=')
    of '<': 
      if tailing('='):
        result = newTokenNodeWithNo(LessEqual)
        idx += 2
      elif tailing('<'):
        inc idx
        if tailing('='):
          result = newTokenNodeWithNo(LeftShiftEqual)
          idx += 2
        else:
          result = newTokenNodeWithNo(LeftShift)
          inc idx
      elif tailing('>'):
        raiseSyntaxError("<> in PEP401 not implemented")
      else:
        addSingleCharToken(Less)
    of '>':
      if tailing('='):
        result = newTokenNodeWithNo(GreaterEqual)
        idx += 2
      elif tailing('>'):
        inc idx
        if tailing('='):
          result = newTokenNodeWithNo(RightShiftEqual)
          idx += 2
        else:
          result = newTokenNodeWithNo(RightShift)
          inc idx
      else:
        addSingleCharToken(Greater)
    of '=': 
      addSingleOrDoubleCharToken(Equal, EqEqual, '=')
    of '.':
      if idx < line.len - 2 and line[idx+1] == '.' and line[idx+2] == '.':
        result = newTokenNodeWithNo(Ellipsis)
        idx += 3
      else:
        addSingleCharToken(Dot)
    of '%':
      addSingleOrDoubleCharToken(Percent, PercentEqual, '=')
    of '{':
      addSingleCharToken(Lbrace)
    of '}':
      addSingleCharToken(Rbrace)
    of '!':
      if tailing('='):
        inc idx
        addSingleCharToken(NotEqual)
      else:
        when fstring_mode:
          addSingleCharToken(Exclamation)
        else:
          raiseSyntaxError("Single ! not allowed")
    of '~':
      addSingleCharToken(Tilde)
    of '^':
      addSingleOrDoubleCharToken(Circumflex, CircumflexEqual, '=')
    of '@':
      addSingleOrDoubleCharToken(At, AtEqual, '=')
    of '\\':
      # Line continuation character: only allowed if directly followed by end-of-line.
      # Otherwise raise an error, e.g. with spaces/tabs
      let j = idx + 1
      if j == line.len:
        lexer.metContChar = true
        idx = line.len
      else:
        raiseSyntaxError("unexpected character after line continuation character")
    else: 
      raiseSyntaxError(fmt"Unknown character {curChar}")
    break # end of while true, which is only for empty between tokens
  assert (not result.isNil) or lexer.cont


proc lexOneLine(lexer: Lexer, line: string, mode: Mode) {.inline.} = 
  # Process one line at a time
  assert line.find('\n') == -1
  var line = line
  let hi = line.high
  if hi >= 0 and line[hi] == '\r':
    line.setLen hi

  var idx = 0
  var indentLevel = 0

  # If previous physical line ended with a backslash continuation,
  # ignore indentation changes for this physical line.
  if lexer.cont:
    lexer.metContChar = false
    # XXX: do not skip leading spaces/tabs but do not alter indent stack,
    #  in case of multiline string literals
  else:
    # Calculate the indentation level based on spaces and tabs
    while idx < line.len:
      case line[idx]
      of ' ':
        indentLevel += 1
        inc(idx)
      of '\t':
        indentLevel += 8 # XXX: Assume a tab equals 8 spaces
        inc(idx)
      else:
        break

    if idx == line.len or line[idx] == '#': # Full of spaces or comment line
      return

    # Compare the calculated indentation level with the stack
    let currentIndent = lexer.indentLevel
    if indentLevel > currentIndent:
      lexer.indentStack.add(indentLevel)
      lexer.add(Token.Indent, idx)
    elif indentLevel < currentIndent:
      while lexer.indentLevel > indentLevel:
        lexer.indentStack.delLast()
        lexer.add(Token.Dedent, idx)
      if lexer.indentLevel != indentLevel:
        raiseSyntaxError "Indentation error", lexer.fileName, lexer.lineNo

    # Update the lexer's current indentation level
    lexer.indentLevel = indentLevel

  # Process the rest of the line for tokens
  while idx < line.len:
    let tok = getNextToken(lexer, line, idx, mode)
    if tok.isNil:
      continue
    # adjust implicit continuation nesting for (), [], {}
    case tok.token
    of Token.Lpar, Token.Lsqb, Token.Lbrace:
      lexer.parenLevel.inc
    of Token.Rpar, Token.Rsqb, Token.Rbrace:
      if lexer.parenLevel > 0: lexer.parenLevel.dec
    else: discard
    lexer.add(tok)
  if not lexer.cont:
    lexer.add(Token.NEWLINE, idx)

proc lexString*(lexer: Lexer, input: string, mode=Mode.File) = 
  assert mode != Mode.Eval # eval not tested

  # interactive mode and an empty line
  if mode == Mode.Single and input.len == 0 and not lexer.tripleStr.within:
    lexer.dedentAll
    lexer.add(Token.NEWLINE, 0)
    inc lexer.lineNo
    addSource(lexer.fileName, input)
    return

  for line in input.split('\n'):
    # lineNo starts from 1
    inc lexer.lineNo
    addSource(lexer.fileName, input)
    lexer.lexOneLine(line, mode)
  when defined(debug_token):
    echo lexer.tokenNodes
  if mode != Mode.Single and lexer.cont:
    raiseSyntaxError("unexpected EOF", lexer.fileName, lexer.lineNo)

  case mode
  of Mode.File:
    lexer.dedentAll
    lexer.add(Token.Endmarker, 0)
  of Mode.Single:
    discard
  of Mode.Eval:
    lexer.add(Token.Endmarker, 0)

