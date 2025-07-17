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

# === history input track ===
type HistoryTrackPos = object
  offset: Natural  ## neg order

proc reset*(self: var HistoryTrackPos) = self.offset = 0

proc stepToPastImpl(self: var HistoryTrackPos) =
  let hi = stream.high
  self.offset =
    if self.offset == hi: hi
    else: self.offset + 1
proc stepToNowImpl(self: var HistoryTrackPos) =
  self.offset =
    if self.offset == 0: 0
    else: self.offset - 1

template getHistoryRecord(self: HistoryTrackPos): untyped =
  stream[stream.high - self.offset]

{.push noconv.}
proc createRange(doc: Document): Range{.importcpp.}
proc setStart(rng: Range, node: Node, pos: int) {.importcpp.}
proc collapse(rng: Range, b: bool) {.importcpp.}
proc addRange(s: Selection, rng: Range){.importcpp.}
{.pop.}

proc setCursorPos(element: Node, position: int) =
  ## .. note:: position is starting from 1, not 0
  # from JS code:
  # Create a new range
  let range = document.createRange()

  # Get the text node
  let textNode = element.firstChild

  # Set the position
  range.setStart(textNode, position)
  range.collapse(true)

  # Apply the selection
  let selection = document.getSelection()
  selection.removeAllRanges()
  selection.addRange(range)

  # Focus the element
  element.focus();


template genStep(pastOrNext){.dirty.} =
  proc `stepTo pastOrNext`*(self: var HistoryTrackPos, input: var Node) =
    self.`stepTo pastOrNext Impl`
    var tup: tuple[prompt, info: kstring]

    tup = self.getHistoryRecord
    if tup.prompt == "":  # is output over input
      # skip this one
      self.`stepTo pastOrNext Impl`
      tup = self.getHistoryRecord

    let hisInp = tup.info
    input.innerHTML = hisInp
    # set cursor to end  (otherwise it'll just be at the begining)
    let le = hisInp.len  # XXX: suitable for Unicode?
    input.setCursorPos(le)

genStep Past
genStep Now

var historyInputPos: HistoryTrackPos


proc pushHistory(prompt: kstring, exp: string) =
  stream.add (prompt, kstring exp)

  historyInputPos.reset

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
        case KeyboardEvent(ev).key  # .keyCode is deprecated
        of "Enter":
          var input = $n.dom.textContent
          pushHistory(prompt, input)
          interactivePython(input)
          n.dom.innerHTML = kstring""
        of "ArrowUp":
          historyInputPos.stepToPast n.dom
        of "ArrowDown":
          historyInputPos.stepToNow n.dom
        else: return
        ev.preventDefault
    )

setRenderer createDom, clientPostRenderCallback=postRenderCallback

