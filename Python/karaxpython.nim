{.used.}
import ./cpython

import ../Utils/compat

import ./lifecycle
import ../Objects/frameobject
import ../Parser/[lexer, parser]
pyInit(@[])

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
            let input = $n.dom.textContent
            echo input
            interactivePython(input)
            n.dom.innerHTML = kstring""
            ev.preventDefault

setRenderer createDom
