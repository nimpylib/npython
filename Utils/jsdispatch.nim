
when defined(js):
  import std/jsffi
  var ibindExpr{.compileTime.}: int
  template bindExpr*[T=JsObject](asIdent; exprOfJs: string) =
    ## helpers to cache exp (make sure `exp` evaluated by js only once)
    bind ibindExpr
    let tmp{.importjs: exprOfJs.}: T
    const `asIdent InJs`* = "_NPython_bindExpr" & $ibindExpr
    static: ibindExpr.inc
    let asIdent*{.exportc: `asIdent InJs`.} = tmp

  template notDecl*(s): string = "(typeof("&s&")==='undefined')"

  bindExpr[bool] notDeno, notDecl"Deno"

  template ifOr*(cond, a, b: string): string = cond&'?'&a&':'&b
  template denoOr(deno, node: string): string =
    bind notDenoInJs
    notDenoInJs.ifOr node, deno
  bindExpr[] notNode, notDecl"process"
  template nodeno*(node, deno, def: string): string =
    ## node or node or def
    bind ifOr, notNodeInJs
    ifOr(notNodeInJs, denoOr(deno, def), node)
  #NOTE: As ./compat.nim uses js top-level import, so the whole JS file is
  # ES module, thus `require` is not defined, which we cannot use here.
  bindExpr[] fsOrDeno, nodeno("(await (import('node:fs')))", "Deno", "null")
  # using `await import` without paran will causes js SyntaxError on non-nodejs

  template fsDeno*(s): untyped =
    bind fsOrDenoInJs
    fsOrDenoInJs & '.' & s & "(@)"
