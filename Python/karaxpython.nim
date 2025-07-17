{.used.}

import std/strutils
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

let info = getVersionString(verbose=true)
const gitRepoUrl{.strdefine.} = ""
const repoInfoPre = "This website is frontend-only. Open-Source at "
include karax/prelude
import karax/kdom
import karax/vstyles

var prompt: kstring

let
  suitHeight = (StyleAttr.height, kstring"wrap-content") # XXX: still too height

template oneReplLineNode(editNodeClasses;
    editable: static[bool]; promptExpr, editExpr): VNode =
  buildHtml:
    tdiv(class="line", style=style(
        (display, kstring"flex"),   # make children within one line
        suitHeight,
    )):
      pre(class="prompt" , style=style(
          suitHeight,
      )):
        promptExpr

      pre(class=editNodeClasses, contenteditable=editable, style=style(
        (flex, kstring"1"),  # without this, it becomes uneditable
        (border, kstring"none"),
        (outline, kstring"none"),
        suitHeight,
      )):
        editExpr

const historyContainerId = "history-container"
var historyNode: Node

# TODO: arrow-up / arrow-down for history
proc pushHistory(prompt: kstring, exp: string) =
  stream.add (prompt, kstring exp)

  # auto scroll down when the inputing line is to go down the view
  let last = historyNode.lastChild
  if last.isNil: return
  last.scrollIntoView(ScrollIntoViewOptions(
    `block`: "start", inline: "start", behavior: "instant"))

const isEditingClass = "isEditing"

# NOTE: do not use add callback for DOMContentLoaded
#  as karax's init is called on windows.load event
#  so to set `clientPostRenderCallback` of setRenderer
proc postRenderCallback() =
  historyNode = document.getElementById(historyContainerId)

  let nodes = document.getElementsByClassName(isEditingClass)
  assert nodes.len == 1, $nodes.len
  let edit = nodes[0]
  edit.focus()

proc createDom(): VNode =
  result = buildHtml(tdiv):
    tdiv(class="header"):
      p(class="info"):
        text info
      when gitRepoUrl.len != 0:
        small: italic(class="repo-info"): # TODO: artistic
          text repoInfoPre
          a(href=gitRepoUrl): text "Github"
    tdiv(class="stream", id=historyContainerId):
      for line in stream:
        let (prompt, content) = line
        tdiv(class="history"):
          oneReplLineNode("expr", false,
            text prompt, text content
          )
    oneReplLineNode("expr " & isEditingClass, true, block:
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
          pushHistory(prompt, input)
          interactivePython(input)
          n.dom.innerHTML = kstring""
          ev.preventDefault
    )

setRenderer createDom, clientPostRenderCallback=postRenderCallback

