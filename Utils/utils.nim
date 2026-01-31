when defined(nimPreviewSlimSystem):
  import std/[assertions]
  export assertions

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

const ShouldnotHere = "Shouldn't be here"
proc noreturnUnreachable*(msg = ShouldnotHere){.noReturn, inline, cdecl.} =
  # let optimizer to eliminate related branch
  doAssert false, msg


template unreachable*(msg = ShouldnotHere) = noreturnUnreachable(msg)
template `!!`*[E: CatchableError](err: typedesc[E]; body): untyped =
  ##[
  XXX:NIM-BUG:
  For expr, DO NOT use `!!` (use `!`_),
   `nim js` may make `x = KeyError!!d[k]` disappear in produced JS code.
  ]##
  try: body
  except E: noreturnUnreachable()

template `!`*[E: CatchableError; T: not void](err: typedesc[E]; e: T): T =
  var res: T
  try: res = e
  except E: noreturnUnreachable()
  res
