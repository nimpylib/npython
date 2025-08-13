
import std/macros
import ./utils

type JsArray*[T] = distinct seq[T]  ## Currently, (as of Nim 2.3.1, seq is just js's Array)

proc newBractetExpr(head, i: NimNode): NimNode = nnkBracketExpr.newTree(head, i)
proc borrowT1Impl(def: NimNode): NimNode =
  ## borrow collection with one generic param and (only) the first param is the collection
  let
    name = def.name
    genericsParams = def[2] # GenericParams
    params = def.params
    self = params[1][0]
  assert genericsParams.len == 1
  let gDefs = genericsParams[0] # IdentDefs
  let T = gDefs[0]

  let castSelf = newCall(bindSym"seq".newBractetExpr T, self)
  var call = newCall(name, castSelf)
  for i in 2..<params.len:  # #0 is restype
     call.add params[i][0]
  
  def.body = if def.kind == nnkIteratorDef: quote do:
      for i in `call`: yield i
    else: call
  def
#macro borrowT1(def) = borrowT1Impl(def)

macro borrowT1s(defs) =
  result = newStmtList()
  for i in defs:
    result.add borrowT1Impl(i)

borrowT1s:
  proc len*[T](self: JsArray[T]): int
  iterator items*[T](self: JsArray[T]): T
  iterator pairs*[T](self: JsArray[T]): (int, T)
  proc `@`*[T](self: JsArray[T]): seq[T]
  proc `[]`*[T](self: JsArray[T], i: int): T
  proc `[]=`*[T](self: var JsArray[T], i: int, v: T)

# we haven't implement such a borrowT:
proc `==`*[T](self, o: JsArray[T]): bool = seq[T](self) == seq[T](o)

proc `$`*[T](self: JsArray[T]): string = dollarImpl(self)  ## returns string like `[1, 2]`

proc newJsArray*[T](): JsArray[T] = discard
proc newJsArray*[T](len: int): JsArray[T] = JsArray[T](newSeq[T](len))
proc newJsArray*[T](oa: openArray[T]): JsArray[T] = JsArray[T](@oa)


when isMainModule:
  static:assert defined(js)

  var arr = newJsArray[int](3)
  echo arr
  arr[0] = 3
  echo arr
