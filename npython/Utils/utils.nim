when defined(nimPreviewSlimSystem):
  import std/[assertions]
  export assertions

import pkg/handy_sugars/assumes
export assumes

type
  # exceptions used internally
  InternalError* = object of CatchableError

  SyntaxError* = ref object of CatchableError
    fileName*: string
    lineNo*: int
    colNo*: int

  # internal error for wrong type of dict function (`hash` and `eq`) return value
  DictError* = object of CatchableError

  # internal error for not implemented bigint lib
  IntError* = object of CatchableError

proc newSyntaxError(msg, fileName: string, lineNo, colNo: int): SyntaxError = 
  new result
  result.msg = msg
  result.fileName = fileName
  assert lineNo > 0, "line no starting from 1"
  result.lineNo = lineNo
  result.colNo = colNo


template raiseSyntaxError*(msg: string, fileName:string, lineNo: int, colNo=0) = 
  raise newSyntaxError(msg, fileName, lineNo, colNo)

