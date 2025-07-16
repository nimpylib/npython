
import ./neval
import ./cpython
import ../Utils/compat

import std/jsffi except require

template isMain(b): bool = isMainModule and b
const
  nodejs = defined(nodejs)
  deno = defined(deno)
  dKarax = defined(karax)
when isMain(nodejs or deno):
  proc bufferAsString(buf: JsObject): string =
    let n = buf.length.to int
    when declared(newStringUninit):
      result = newStringUninit(n)
      for i in 0..<n:
        result[i] = buf[i].to char
    else:
      for i in 0..<n:
        result.add buf[i]
  when nodejs:
    {.emit: """/*INCLUDESECTION*/
    import {existsSync, readFileSync} from 'node:fs';
    import {argv} from 'node:process';
    """.}
    let argv{.importc, nodecl.}: JsObject
    proc existsSync(fp: cstring): bool {.importc.}
    proc readFileSync(fp: cstring): JsObject {.importc.}
    proc fileExists(fp: string): bool =
      existsSync(fp.cstring)
    proc readFile(fp: string): string =
      let buf = readFileSync(fp.cstring)
      # without {'encoding': ...} option, Buffer returned
      bufferAsString buf
    const argsStart = 2
  else:
    const argsStart = 0
    {.emit: """/*INCLUDESECTION*/
    import { existsSync } from "jsr:@std/fs/exists";
    """.}

    let argv{.importjs: "Deno.args".}: JsObject
    type ExistsOption = object
      isFile: bool
    proc existsSync(fp: cstring, options: ExistsOption): bool {.importc.}
    proc fileExists(fp: string): bool =
      existsSync(fp.cstring, ExistsOption{isFile: true})
    proc readFileSync(fp: cstring): JsObject#[Uiny8Array]#{.importjs: "Deno.readFileSync(@)".}
    proc readFile(fp: string): string =
      let buf = fp.cstring.readFileSync
      bufferAsString buf

  proc wrap_nPython(args: seq[string]){.mayAsync.} =
    mayAwait nPython(args, fileExists, readFile)

  proc commandLineParams(): seq[string] =
    ## minic std/cmdline's
    let hi = argv.length.to int
    let argn = hi - argsStart
    result = newSeqOfCap[string](argn)
    for i in argsStart ..< hi:
      result.add $(argv[i].to cstring)

  mayWaitFor main(commandLineParams(), wrap_nPython)

else:
  import ./lifecycle
  pyInit(@[])
  when isMain(dkarax):
    import ../Objects/frameobject
    import ../Parser/[lexer, parser]
    var finished = true
    var rootCst: ParseNode
    let lexerInst = newLexer("<stdin>")
    var prevF: PyFrameObject
    proc interactivePython(input: string): bool {. exportc, discardable .} =
      echo input
      if finished:
        rootCst = nil
        lexerInst.clearIndent
      return parseCompileEval(input, lexerInst, rootCst, prevF, finished)

    const prompt = ">>> "

    include karax/prelude
    import karax/kdom

    proc createDom(): VNode =
      result = buildHtml(tdiv):
        tdiv(class="stream"):
          echo stream.len
          for line in stream:
            let (prompt, content) = line
            tdiv(class="line"):
              p(class="prompt"):
                if prompt.len == 0:
                  text kstring" "
                else:
                  text prompt
              p:
                text content
        tdiv(class="line editline"):
          p(class="prompt"):
            text prompt
          p(class="edit", contenteditable="true"):
            proc onKeydown(ev: Event, n: VNode) =
              if KeyboardEvent(ev).keyCode == 13:
                let input = n.dom.innerHTML
                echo input
                interactivePython($input)
                n.dom.innerHTML = kstring""
                ev.preventDefault

    setRenderer createDom
  elif isMainModule:
    mayWaitFor interactiveShell()
