

import ../Python/[
  warnings, versionInfo,
]
import ../Objects/[
  pyobject, exceptions
]
import ../Utils/[
  utils,
  translateEscape,
]
import lexerTypes

template handleEscape(asSyntaxErrorMsg) =
    let category = 
      when PyMinor >= 12: pySyntaxWarningObjectType
      else: pyDeprecationWarningObjectType
    let err = warnExplicit(category, arg, info.fileName, info.line)
    if err.isNil: return
    if err.pyType == category:
      #[Replace the Syntax/DeprecationWarning exception with a SyntaxError
               to get a more accurate error report]#
      raiseSyntaxError(asSyntaxErrorMsg, info.fileName, info.line, info.column)
    else:
      #TODO:string_parser spread the exception as is, instead of always raising an type of exception
      let serr = try: ": " & $err except Exception: ""
      raiseAssert "warnings.warn raises an exception: " & serr

proc lexMessage(info: LineInfo, kind: TranslateEscapeErr, _: string){.raises: [SyntaxError].} =
  let arg = $kind
  case kind
  #TODO:string_parser change function signature to pass another string to capture current escape string
  of teeBadEscape:
    handleEscape """
"\%c" is an invalid escape sequence. Did you mean "\\%c"? A raw string is also an option."""
  of teeBadOct:
    handleEscape """
"\%.3s" is an invalid escape octal sequence. Did you mean "\\%.3s"? A raw string is also an option."""
  else:
    raiseSyntaxError(arg, info.fileName, info.line, info.column)

template decode_string_with_escapes(lex; s: string): string =
  lex.lineInfo.fileName = L.fileName
  lex.lineInfo.line = L.lineNo
  lex.translateEscape

{.push raises: [SyntaxError].}
proc decode_unicode_with_escapes*(L: lexerTypes.Lexer, s: string): string =
  var lex = newLexer[true](s, lexMessage)
  lex.decode_string_with_escapes s
  
proc decode_bytes_with_escapes*(L: lexerTypes.Lexer, s: string): string =
  var lex = newLexer[false](s, lexMessage)
  lex.decode_string_with_escapes s
{.pop.}
