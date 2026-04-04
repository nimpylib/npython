import std/macros
import std/strutils
type
  IntFlag*[E: enum] = distinct cint
const sizeofIntFlag* = sizeof(cint)  ## internal

proc `or`*[E](a, b: IntFlag[E]): IntFlag[E] =  IntFlag[E] a.cint or b.cint
proc `==`*[E](a, b: IntFlag[E]): bool = a.cint == b.cint
proc `==`*[E](a: IntFlag[E], b: E): bool = a.cint == b.cint
proc `$`*[E](x: IntFlag[E]): string = $E & '(' & $cint(x) & ')'

macro fillAsEnumFromStmtList(name: untyped; pure: static[bool]; stmts: untyped) =
  var fields = newSeqOfCap[NimNode](stmts.len)
  var doc: NimNode
  for e in stmts:
    if e.kind == nnkCommentStmt:
      doc = e
      continue
    if e.kind == nnkIdent:
      fields.add e
      continue

    e.expectLen 2
    var rhs = e[1]
    template wrapVal(ele) =
      ele = newCall(bindSym"IntFlag", ele)
    if rhs.kind == nnkTupleConstr: wrapVal rhs[1]
    else: wrapVal rhs
    fields.add nnkEnumFieldDef.newTree(e[0], rhs)
  result = newEnum(name, fields, pure=pure, public=true)
  if not doc.isNil:
    var s = result.repr
    # in format:
    #[
    type
      xx ...
    ]#
    let ls = s.split('\n', 2)
    const NL = '\n'
    s = ls[0] & NL & ls[1] & NL & "    ##[ " & doc.strVal & "]##" & NL & ls[2]
    result = parseStmt s

template prepareIntFlagOr*{.dirty.} =
  template orImpl[E](a, b): untyped = IntFlag[E](a) or IntFlag[E] b
  {.push used.}
  template `|`[E: enum](a: E, b: int): IntFlag[E] = orImpl[E](a, b)
  template `|`[E: enum](a: int, b: E): IntFlag[E] = orImpl[E](a, b)
  template `|`[E: enum](a, b: E): IntFlag[E] = orImpl[E](a, b)
  template `|`[E: enum](a: IntFlag[E], b: E): IntFlag[E] = a or IntFlag[E] b
  {.pop.}

template maskImpl(a, b): bool =
  let ib = cint(b); (cint(a) and ib) == ib
template declareIntFlag*(name; pure; body) =
  bind fillAsEnumFromStmtList, IntFlag, maskImpl

  fillAsEnumFromStmtList name, true, body

  converter toIntFlag*(x: name): IntFlag[name] = IntFlag[name](x)
  proc `|`*(a, b: name): IntFlag[name] = a or b
  proc `&`*(a, b: name): bool = maskImpl(a, b)
  proc `&`*[E](a: IntFlag[E], b: name): bool = maskImpl(a, b)

template declareIntFlag*(name; body) = declareIntFlag(name, true, body)


when isMainModule:
  prepareIntFlagOr
  declareIntFlag PyFlags:
    ## asd
    ## asddsa
    A
    B
  echo PyFlags.A | PyFlags.B
  let f: IntFlag[PyFlags] = PyFlags.A
  assert f & PyFlags.A

  declareIntFlag PyFlags2:
    ## asd
    ## asddsa
    A2 = 0x10
    B2 = 0x20
    B3 = (11|PyFlags2.B2)
  echo PyFlags.A | PyFlags.B

  type IF = IntFlag[PyFlags|PyFlags2]
  var f2: IF
  discard f2 & PyFlags.B

