
const Js = defined(js)

template jsOr(a, b): untyped =
  when Js: a else: b

when Js:
  import std/jsffi
  import ./jsdispatch
  proc bufferAsString(buf: JsObject): string =
    let n = buf.length.to int
    when declared(newStringUninit):
      result = newStringUninit(n)
      for i in 0..<n:
        result[i] = buf[i].to char
    else:
      for i in 0..<n:
        result.add buf[i]

  # without {'encoding': ...} option, Buffer returned
  proc readFileSync(p: cstring): JsObject{.importjs: fsDeno"readFileSync".}
  proc writeFileSync(p, data: cstring){.importjs: fsDeno"writeFileSync".}
  proc existsSync(fp: cstring): bool{.importjs: fsDeno"existsSync".}
  #XXX: not suitable but cannot found another handy api

  
  let argsStart =
    if notDeno: 2
    else: 0

  bindExpr[] argv, nodeno("process.argv", "Deno.args", "[]")

  proc commandLineParamsImpl(): seq[string] =
    ## minic std/cmdline's
    let hi = argv.length.to int
    let argn = hi - argsStart
    result = newSeqOfCap[string](argn)
    for i in argsStart ..< hi:
      result.add $(argv[i].to cstring)
else:
  when defined(nimPreviewSlimSystem):
    import std/syncio
  import std/os
proc readFileCompat*(fp: string): string = jsOr readFileSync(cstring fp).bufferAsString, readFile(fp)
proc writeFileCompat*(fp, data: string) = jsOr writeFileSync(cstring fp, cstring data), writeFile(fp, data)
proc fileExistsCompat*(fp: string): bool = jsOr existsSync(cstring fp), fileExists(fp)


proc commandLineParamsCompat*(): seq[string] =
  jsOr commandLineParamsImpl(), commandLineParams()

