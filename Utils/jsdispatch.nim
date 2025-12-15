## this module's APIs is unstable
when defined(js):
  import std/jsffi
  export jsffi
  var ibindExpr{.compileTime.}: int
  template bindExpr*[T=JsObject](asIdent; exprOfJs: string) =
    ## helpers to cache exp (make sure `exp` evaluated by js only once)
    bind ibindExpr
    let tmp{.importjs: exprOfJs.}: T
    const `asIdent InJs`* = "_NPython_bindExpr" & $ibindExpr
    static: ibindExpr.inc
    let asIdent*{.exportc: `asIdent InJs`.} = tmp

  template notDecl*(s): string = "(typeof("&s&")==='undefined')"
  template `&&`(a, b: string): string = "("&a&"&&"&b&")"
  template `||`(a, b: string): string = "("&a&"||"&b&")"
  template `!`(a: string): string = "!("&a&")"


  bindExpr[bool] notDeno, notDecl"Deno"

  template ifOr*(cond, a, b: string): string = cond&'?'&a&':'&b
  template denoOr(deno, node: string): string =
    bind notDenoInJs
    notDenoInJs.ifOr node, deno
  bindExpr[bool] notHasProcess, notDecl"process"  # as Deno also has `process`
  bindExpr[bool] notNode, (notHasProcessInJs || !notDenoInJs)
  template nodeno*(node, deno, def: string): string =
    ## node or node or def
    bind ifOr, notNodeInJs
    ifOr(notNodeInJs, denoOr(deno, def), node)
  #NOTE: As ./compat.nim uses js top-level import, so the whole JS file is
  # ES module, thus `require` is not defined, which we cannot use here.
  #template genX(name; s){.dirty.} =
  func importNodeExpr(s: string): string =
    "(await (import('node:"&s&"')))"
  template genXorDeno(name; s){.dirty.} =
    bindExpr[] name, nodeno(importNodeExpr s, "Deno", "null")
  template genX(name; s){.dirty.} =
    bindExpr[] name, ifOr(notNodeInJs && notDenoInJs, "null", importNodeExpr s)
  # using `await import` without paran will causes js SyntaxError on non-nodejs
  genXorDeno fsOrDeno, "fs"
  genXorDeno ttyOrDeno, "tty"  # for .isatty
  genX fsMod, "fs"

  template jsFuncExpr(js, name: string): untyped{.dirty.} =
    js & '.' & name & "(@)"
  
  template genPragma(name, jsExp){.dirty.} =
    template name*(s): untyped =
      bind jsExp
      bind jsFuncExpr
      jsFuncExpr(jsExp, s)
  genPragma fsDeno, fsOrDenoInJs
  genPragma fs, fsModInJs
