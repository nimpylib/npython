
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
  Lookup,
  StopIter,
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
  Syntax: "end_lineno,end_offset,filename,lineno,msg,offset,print_file_and_line,text",
  OS: "myerrno,strerror,filename,filename2,winerror,written",
}
iterator extraAttrs*(tok: ExceptionToken): NimNode =
  ExcAttrs.withValue(tok, value):
    for n in value.split(','):
      yield ident n


type BaseExceptionToken*{.pure.} = enum
  ## subclasses of `BaseException` except `Exception` and `BaseExceptionGroup`
  BaseException = 0
  SystemExit GeneratorExit KeyboardInterrupt 

iterator extraAttrs*(tok: BaseExceptionToken): NimNode =
  # only SystemExit has a attr: code
  if tok == SystemExit: yield ident"code"
