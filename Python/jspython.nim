
import ./neval
import ../Parser/[lexer, parser]
import ./cpython
import ../Objects/frameobject

var finished = true
var rootCst: ParseNode
let lexerInst = newLexer("<stdin>")
var prevF: PyFrameObject

proc interactivePython(input: cstring): bool {. exportc .} =
  echo input
  return parseCompileEval($input, lexerInst, rootCst, prevF, finished)

import std/jsffi

when isMainModule and defined(nodejs):
  let fs = require("fs");
  proc fileExists(fp: string): bool =
    fs.existsSync(fp.cstring).to bool
  proc readFile(fp: string): string =
    let buf = fs.readFileSync(fp.cstring)
    let n = buf.length.to int
    # without {'encoding': ...} option, Buffer returned
    when declared(newStringUninit):
      result = newStringUninit(n)
      for i in 0..<n:
        result[i] = buf[i].to char
    else:
      for i in 0..<n:
        result.add buf[i]

  proc wrap_nPython(args: seq[string]) =
    nPython(args, fileExists, readFile)
  
  proc commandLineParams(): seq[string] =
    ## minic std/cmdline's

    let process = require("process");
    let start = 2
    let argv = process.argv #.slice(start)
    let hi = argv.length.to int
    let argn = hi - start
    result = newSeqOfCap[string](argn)
    for i in start ..< hi:
      result.add $(argv[i].to cstring)

  main(commandLineParams(), wrap_nPython)

# karax not working. gh-86
#[
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

]#
