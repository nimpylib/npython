

import ../Python/[
  warnings, versionInfo,
]
import ../Objects/[
  pyobject,
]
import ../Utils/[
  utils,
  translateEscape,
]
import lexerTypes

proc lexMessage(info: LineInfo, kind: TranslateEscapeErr, _: string){.raises: [SyntaxError].} =
  let arg = $kind
  case kind
  of teeBadEscape:
    warnExplicit(
      when PyMinor >= 12: pySyntaxWarningObjectType
      else: pyDeprecationWarningObjectType
      ,
      arg, info.fileName, info.line
    )
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
