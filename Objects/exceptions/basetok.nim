
import std/[
  tables, macros
]
from std/strutils import split
export tables

type ExceptionToken* {. pure .} = enum
  Base,  ## `Exception`, not `BaseException`
  Name,
  Type,
  Arithmetic,
  Attribute,
  Buffer,
  Value,
  Reference,
  Lookup,
  StopIter,
  StopAsyncIter,
  Lock,
  Import,
  Assertion,
  Runtime,
  Syntax,
  Memory,
  System,
  OS,
  EOF

const ExcAttrs = toTable {
  # values will be `split(',')`
  Name: "name",
  Attribute: "name,obj",
  StopIter: "value",
  Import: "msg,name,name_from,path",
  #FIXME: `_metadata` over metadata
  Syntax: "msg,filename,lineno,offset,text,end_lineno,end_offset,print_file_and_line,metadata",
  OS: "errno,strerror,filename,filename2,winerror",
}

template yieldRes(value) =
  for n in value.split(','):
    yield ident n

when (NimMajor, NimMinor, NimPatch) > (2,3,1):
 iterator extraObjAttrs*(tok: ExceptionToken): NimNode =
  ExcAttrs.withValue(tok, value):
    yieldRes value
else:
 # nim-lang/Nim#25162
 iterator extraObjAttrs*(tok: ExceptionToken): NimNode =
    let value = ExcAttrs.getOrDefault(tok, "")
    if value != "":
      yieldRes value

type BaseExceptionToken*{.pure.} = enum
  ## subclasses of `BaseException` except `Exception` and `BaseExceptionGroup`
  BaseException = 0
  SystemExit GeneratorExit KeyboardInterrupt BaseExceptionGroup

iterator extraObjAttrs*(tok: BaseExceptionToken): NimNode =
  # only SystemExit has a attr: code
  case tok
  of SystemExit: yield ident"code"
  of BaseExceptionGroup:
    yield ident"message"
    yield ident"exceptions"
  else: discard

iterator extraTypedAttrs*(tok: ExceptionToken | BaseExceptionToken): (NimNode, NimNode) =
  when tok is ExceptionToken:
    if tok == ExceptionToken.OS: yield (ident"written", ident"int")
