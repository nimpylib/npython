{.used.}

import std/strutils
import ./cpython

import ../Utils/compat

import ./lifecycle
import ../Objects/frameobject
import ../Parser/[lexer, parser]
pyInit(@[])
proc subsNonbreakingSpace(s: var string) =
  ## The leading space, if with following spaces, in on contenteditable element
  ## will become `U+00A0` (whose utf-8 encoding is c2a0)
  s = s.replace("\xc2\xa0", " ")


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

let info = getVersionString(verbose=true)

include karax/prelude
import karax/kdom
import karax/vstyles

var prompt: kstring

let
  suitHeight = (StyleAttr.height, kstring"wrap-content") # XXX: still too height
  preserveSpaces = (whiteSpace, kstring"pre") # ensure spaces remained
  monospace = (StyleAttr.font_family, kstring"monospace")
template oneReplLineNode(editable: static[bool]; promptExpr, editExpr): VNode{.dirty.} =
  buildHtml:
    tdiv(class="line", style=style(
        (display, kstring"flex"),   # make children within one line
        suitHeight,
    )):
      p(class="prompt" , style=style(
          suitHeight, monospace, preserveSpaces,
      )):
        promptExpr

      p(class="edit", contenteditable=editable, style=style(
        (flex, kstring"1"),  # without this, it becomes uneditable
        (border, kstring"none"),
        (outline, kstring"none"),
        suitHeight, monospace, preserveSpaces,
      )):
        editExpr
# TODO: arrow-up / arrow-down for history
const historyContainerId = "history-container"
proc pushHistory(prompt: kstring, exp: string) =
  stream.add (prompt, kstring exp)

  # auto scroll down when the inputing line is to go down the view
  let historyNode = document.getElementById(historyContainerId)
  let last = historyNode.lastChild
  if last.isNil: return
  last.scrollIntoView(ScrollIntoViewOptions(
    `block`: "start", inline: "start", behavior: "instant"))

proc createDom(): VNode =
  result = buildHtml(tdiv):
    tdiv(class="header"):
      p(class="info"):
        text info
    tdiv(class="stream", id=historyContainerId):
      for line in stream:
        let (prompt, content) = line
        tdiv(class="history"):
          oneReplLineNode(false,
            text prompt, text content
          )
    oneReplLineNode(true, block:
      prompt = if finished:
        kstring">>> "
      else:
        kstring"... "
      text prompt
    ,
    block:
      proc onKeydown(ev: Event, n: VNode) =
        if KeyboardEvent(ev).keyCode == 13:
          var input = $n.dom.textContent
          input.subsNonbreakingSpace
          pushHistory(prompt, input)
          interactivePython(input)
          n.dom.innerHTML = kstring""
          ev.preventDefault
    )

setRenderer createDom
