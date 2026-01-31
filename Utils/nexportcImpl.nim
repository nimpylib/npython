
import std/macros
import ./nexportc_header

proc toIdent(n: NimNode): NimNode =
  expectKind n, {nnkIdent, nnkSym}
  ident n.strVal
proc withIdLast2(e, last1, last2: NimNode): NimNode =
  result = e.copyNimNode
  let hi = e.len-2
  for i in 0..<hi:
    result.add e[i].toIdent
  result.add last1
  result.add last2

proc newLibPragmas(old_pragma: NimNode): NimNode =
  var pragmas = if old_pragma.len > 0:
    old_pragma.copyNimTree
  else: newNimNode nnkPragma
  pragmas.add ident"exportc"
  pragmas.add ident"dynlib"
  pragmas.add ident"cdecl"
  pragmas

proc cvtResType(def: NimNode) =
  ## assuming def.body is an expression (a simple expression function)
  let params = def.params
  params[0] = ident"cint"
  let old_body = def.body
  def.body = quote do:
    if not `old_body`:
      return cint(-1)

proc npyexportcImpl(def: NimNode, flags: NPyExportcFlagsSet): NimNode =
  let disallowBoolRet = flags & boolRetAsCInt
  let stringConv = not (flags & noStringConv)
  let params = def.params
  template retOld =
    result = def.copyNimTree
    result.pragma = newLibPragmas def.pragma
    return
  result = newStmtList(def)
  let cparams = params.copyNimNode
  cparams.add params[0]  # restype
  let nam = def.name
  var cname = ident nam.strVal
  if nam.isExported:
    cname = cname.postfix"*"
  
  let call = newCall(nam)
  let cstr = ident"cstring"
  let body = newStmtList()
  template toStr(n): NimNode = n.prefix"$"
  var needCvtArg = false
  for i in 1..<params.len:
    let e = params[i]
    template addArgs =
      let ne = e.copyNimNode
      for ii in 0..<e.len-2:
        let arg = e[ii].toIdent
        ne.add arg
        call.add arg
      ne.add e[^2]
      ne.add e[^1]
      cparams.add ne
    template addWithNillable(typ) =
      # for identDefs in proc: `p1, p2: last1 = last2`
      needCvtArg = true
      cparams.add e.withIdLast2(typ, newEmptyNode())
      for ii in 0..<e.len-2:
        let arg{.inject.} = e[ii].toIdent
        body.add quote do:
          assert not `arg`.isNil
        call.add arg.toStr

    e.expectKind nnkIdentDefs
    var typ = e[^2]
    if typ.kind == nnkEmpty:
      let last = e[^1]
      typ = if last.kind == nnkEmpty:
        e[^3]
      else:
        last
    if stringConv and typ.typeKind == ntyString:
      addWithNillable cstr
      continue
    addArgs
  when defined(debug_nexportc):
    defer: echo result.repr
  let resType = params[0]
  let retBool = resType.typeKind == ntyBool
  if not needCvtArg: #[ also means cannot be overloaded ]#
    if disallowBoolRet:
      if retBool:
        error "nexportc: disallowBoolRet=true for " &
          "function returning bool but cannot overloaded",
          resType
    retOld
  body.add call

  var i = 0
  template push(e) =
    cdef.add e
    i.inc
  template still: untyped = def[i]
  let cdef = def.copyNimNode
  push cname
  push still
  push still
  push cparams
  push newLibPragmas still
  push still
  push body
  if disallowBoolRet and retBool:
    cdef.cvtResType
  result.add cdef

macro npyexportc*(def: typed): untyped = npyexportcImpl def, NPyExportcFlagsSet 0

macro npyexportcSet*(flags: static NPyExportcFlags, def: typed): untyped = npyexportcImpl def, flags
macro npyexportcSet*(flags: static NPyExportcFlagsSet, def: typed): untyped = npyexportcImpl def, flags

when isMainModule:
  proc defval: int = 3
  using str: string
  proc init(){.npyexportc.} = echo "init"
  proc f*(str; flags=defval()): bool{.cdecl, npyexportcSet(boolRetAsCInt).} =
    echo str
    echo "hello"
    true
  assert f(
    "he",
  )
  init()
  let p = cstring"he"
  assert 0 == f(
    p,
  )

  proc g*(str): int{.cdecl, npyexportc.} =
    echo str
    echo "world"
    42
  assert 42 == g(
    "wo",
  )
