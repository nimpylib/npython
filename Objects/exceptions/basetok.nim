
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
  Value,
  Lookup,
  StopIter,
  Lock,
  Import,
  Assertion,
  Runtime,
  Syntax,
  Memory,
  KeyboardInterrupt,  #TODO:BaseException shall be subclass of BaseException
  System,

const ExcAttrs = toTable {
  # values will be `split(',')`
  Name: "name",
  Attribute: "name,obj",
  StopIter: "value",
  Import: "msg,name,name_from,path",
  Syntax: "end_lineno,end_offset,filename,lineno,msg,offset,print_file_and_line,text"
}
iterator extraAttrs*(tok: ExceptionToken): NimNode =
  ExcAttrs.withValue(tok, value):
    for n in value.split(','):
      yield ident n

