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

  # internal error for keyboard interruption
  InterruptError* = object of OSError  ## Python's is inherited from OSError

proc newSyntaxError(msg, fileName: string, lineNo, colNo: int): SyntaxError = 
  new result
  result.msg = msg
  result.fileName = fileName
  result.lineNo = lineNo
  result.colNo = colNo


template raiseSyntaxError*(msg: string, fileName:string, lineNo=0, colNo=0) = 
  raise newSyntaxError(msg, fileName, lineNo, colNo)


template unreachable*(msg = "Shouldn't be here") = 
  # let optimizer to eliminate related branch
  when not defined(release):
    raise newException(InternalError, msg)
