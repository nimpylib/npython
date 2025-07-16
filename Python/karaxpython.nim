{.used.}

import std/strutils
proc subsNonbreakingSpace(s: var string) =
  ## The leading space, if with following spaces, in on contenteditable element
  ## will become `U+00A0` (whose utf-8 encoding is c2a0)
  s = s.replace("\xc2\xa0", " ")

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
            var input = $n.dom.textContent
            input.subsNonbreakingSpace
            interactivePython(input)
            n.dom.innerHTML = kstring""
            ev.preventDefault

setRenderer createDom
