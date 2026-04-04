{.used.}

import std/strutils
from std/sugar import capture, `=>`
from std/jsffi import JsObject, jsTypeof
import ./[cpython, pythonrun,]

import ../Utils/[compat, fileio,]

import ./lifecycle
import ../Objects/[frameobject, stringobject,]
import ../Parser/[lexer, parser]
Py_Initialize()

let info = getVersionString(verbose=true)
const gitRepoUrl{.strdefine.} = ""
const repoInfoPre = "This website is frontend-only. Open-Source at "

include karax/prelude
import karax/kdom
import karax/vstyles

#let suitHeight = (StyleAttr.height, kstring"auto") # XXX: still too height
let TopBottom = kstring"0.08rem"
proc hstyle(pairs: varargs[(StyleAttr, kstring)]): VStyle =
  result = style(
    (marginTop, TopBottom),
    (marginBottom, TopBottom),
  )
  for (a, v) in pairs:
    result.setAttr a, v

template oneReplLineNode(editNodeClasses;
    editable: static[bool]; promptExpr, editExpr): VNode =
  buildHtml:
    tdiv(class="line", style=hstyle(
        (display, kstring"flex"),   # make children within one line
    )):
      pre(class="prompt" , style=hstyle()):
        promptExpr

      pre(class=editNodeClasses, contenteditable=editable, style=hstyle(
        (flex, kstring"1"),  # without this, it becomes uneditable
        (border, kstring"none"),
        (outline, kstring"none"),
        (wordBreak, kstring"break-all"),  # break anywhere, excluding CJK
        #(lineBreak, kstring"anywhere"),  # break anywhere, for CJK, not sup by karax
        #(wordWrap, kstring"anywhere"),   # alias of overflow-wrap,  not sup by karax
        (whiteSpace, kstring"pre-wrap"),  # Preserve spaces and allow wrapping
      )):
        editExpr

const historyContainerId = "history-container"
var historyNode: Node

# === history input track ===
import std/options
type
  Historyinfo = tuple[prompt, info: kstring]
  HistoryTrackPos = object
    offset: Natural  ## neg order
    incomplete: Option[HistoryInfo]
    useInComplete: bool

proc pushInCompleteHistory*(self: var HistoryTrackPos, ps, inp: kstring) =
  self.incomplete = some (ps, inp)

proc popInCompleteHistory*(self: var HistoryTrackPos) =
  if self.incomplete.isSome:
    self.incomplete = none HistoryInfo

proc reset*(self: var HistoryTrackPos) = self.offset = 0

proc stepToPastImpl(self: var HistoryTrackPos) =
  let hi = stream.high
  if self.useInComplete:
    self.useInComplete = false
    return
  self.offset =
    if self.offset == hi: hi
    else: self.offset + 1
proc stepToNowImpl(self: var HistoryTrackPos) =
  self.offset =
    if self.offset == 0:
      if self.incomplete.isSome:
        self.useInComplete = true
      0
    else: self.offset - 1

template getHistoryRecord(self: HistoryTrackPos): untyped =
  if self.useInComplete:
    assert self.incomplete.isSome
    self.incomplete.unsafeGet()
  else: stream[stream.high - self.offset]

{.push noconv.}
proc createRange(doc: Document): Range{.importcpp.}
proc setStart(rng: Range, node: Node, pos: int) {.importcpp.}
proc collapse(rng: Range, b: bool) {.importcpp.}
proc addRange(s: Selection, rng: Range){.importcpp.}
{.pop.}

import std/jsconsole
proc setCursorPos(element: Node, position: int) =
  ## .. note:: position is starting from 1, not 0
  # from JS code:
  # Create a new range
  let range = document.createRange()

  # Get the text node
  let textNode = element.firstChild

  # Set the position
  if textNode.isNil:
    # happend if last incomplete history input is empty
    return
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
  let incomplete = historyNode.lastChild
  if incomplete.isNil: return
  incomplete.scrollIntoView(ScrollIntoViewOptions(
    `block`: "start", inline: "start", behavior: "instant"))


proc runLocalPy(ev: Event, _: VNode) =
  let input = document.createElement("input")
  input.setAttribute("type", "file")
  input.setAttribute("multiple", "")
  input.onchange = proc (e: Event) =
    let fileInput = #[input]# e.target

    type
      Promise[T] = ref object of JsObject
      FileList = ref object of JsObject
      File = ref object of Blob

    proc len(self: FileList): int {.importjs: "#.length".}
    proc item(self: FileList, idx: int): File {.importcpp.}

    proc name(_: File): cstring{.importjs: "#.name".}
    proc text(_: File): Promise[cstring]{.importcpp.}

    proc then[T; P: proc](_: Promise[T]; cb: P){.importcpp.}

    proc files(_: typeof(fileInput)): FileList{.importjs: "#.files".}
    let inputs = fileInput.files
    #[proc readAsText(_: FileReader, blob: File){.importcpp.}
    # readAsArrayBuffer
    new_FileReader().onload = proc (ev: Event) =
      let t = ev.target#[reader]#
      proc result(_: typeof(t)): cstring{.importjs: "#.result".}
      ...]#
    for i in 0..<inputs.len:
      #reader.readAsText(inputs.item(i))
      let file = inputs.item(i)
      let filename = $file.name
      capture filename:
        file.text().then((cs: cstring)=>(
          pushHistory(kstring"###>Run File Isolatedly: ", filename);
          let suc = PyRun_SimpleString($cs)
          #TODO: if not suc: ...
          pushHistory(kstring"###>Run File successful: ", $suc)
          redraw()
        ))
  input.click()

const isEditingClass = "isEditing"

proc getInputNode: auto =
  let nodes = document.getElementsByClassName(isEditingClass)
  assert nodes.len == 1, $nodes.len
  let edit = nodes[0]
  edit

# NOTE: do not use add callback for DOMContentLoaded
#  as karax's init is called on windows.load event
#  so to set `clientPostRenderCallback` of setRenderer
proc postRenderCallback() =
  historyNode = document.getElementById(historyContainerId)
  getInputNode().focus()

const fstdin = "<stdin>"
var pyrunner = newPyExecutor fstdin

var prompt: kstring
proc createDom(): VNode =
  result = buildHtml(tdiv):
    tdiv(class="top-menu", style=style(
        (position, kstring"sticky"),
        (top, kstring"0"),  # keep always on top
        (display, kstring"flex"),  # show children horizontally
      )):
      button(onclick=runLocalPy): text "Run Local .py File"
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
      prompt = kstring pyrunner.nextPrompt
      text prompt
    ,
    block:
      proc onKeydown(ev: Event, n: VNode) =
        template getCurInput: kstring = n.dom.textContent
        case KeyboardEvent(ev).key  # .keyCode is deprecated
        of "Enter":
          historyInputPos.popInCompleteHistory()
          let kInput = getCurInput()
          let input = $kInput
          pushHistory(prompt, input)
          pyrunner.feed input
          n.dom.innerHTML = kstring""
        of "ArrowUp":
          let kInput = getCurInput()
          historyInputPos.pushIncompleteHistory(prompt, kInput)
          historyInputPos.stepToPast n.dom
        of "ArrowDown":
          historyInputPos.stepToNow n.dom
        else: return
        ev.preventDefault
    )

setRenderer createDom, clientPostRenderCallback=postRenderCallback

