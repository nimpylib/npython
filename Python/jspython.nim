
import ./neval
import ../Parser/[lexer, parser]
import ./cpython
import ../Objects/frameobject
import ../Utils/compat

import std/jsffi except require

template isMainDefined(m): bool = isMainModule and defined(m)
when isMainDefined(nodejs):
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
    let n = buf.length.to int
    # without {'encoding': ...} option, Buffer returned
    when declared(newStringUninit):
      result = newStringUninit(n)
      for i in 0..<n:
        result[i] = buf[i].to char
    else:
      for i in 0..<n:
        result.add buf[i]

  proc wrap_nPython(args: seq[string]){.mayAsync.} =
    mayAwait nPython(args, fileExists, readFile)

  proc commandLineParams(): seq[string] =
    ## minic std/cmdline's
    let start = 2
    let hi = argv.length.to int
    let argn = hi - start
    result = newSeqOfCap[string](argn)
    for i in start ..< hi:
      result.add $(argv[i].to cstring)

  mayWaitFor main(commandLineParams(), wrap_nPython)

elif isMainDefined(karax):
  var finished = true
  var rootCst: ParseNode
  let lexerInst = newLexer("<stdin>")
  var prevF: PyFrameObject

  proc interactivePython(input: cstring): bool {. exportc, discardable .} =
    echo input
    return parseCompileEval($input, lexerInst, rootCst, prevF, finished)

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
