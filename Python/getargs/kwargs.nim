

import std/macros
import ../../Objects/[
  pyobject,
  exceptions,
  stringobject,
  dictobject,
]
import ../../Include/cpython/pyerrors
import ./[tovalsBase, tovalUtils, paramsMeta]
export tovalsBase, paramsMeta

proc PyArg_ValidateKeywordArguments*(kwargs: PyDictObject): PyTypeErrorObject =
  if not kwargs.hasOnlyStringKeys:
    return newTypeError newPyAscii"keywords must be strings"

proc PyArg_ValidateKeywordArguments*(kwargs: PyObject): PyBaseErrorObject =
  if not kwargs.ofPyDictObject:
    return PyErr_BadInternalCall()
  PyArg_ValidateKeywordArguments PyDictObject kwargs

proc PyArg_UnpackKeywords*(kwargs: PyDictObject; keywords: openArray[string]): seq[PyObject] =
  for k in keywords:
    let v = kwargs.getOptionalItem(newPyStr k)
    if v.isNil: return
    result.add v

const
  unexpKwMsgPart = "() got an unexpected keyword argument "
  quoteC = '\''


template lukImpl(exc; kwargs: PyDictObject, v, k; parseBlk){.dirty.} =
  bind pop, newPyStr, tovalAux
  block:
    var res: PyObject
    if kwargs.pop(newPyStr k, res):
      exc = tovalAux(res, v)
      if not exc.isNil:
        break parseBlk


template chkUnexpectedKey(exc, kwargs, fname){.dirty.} =
  bind keys, unexpKwMsgPart, `$`, quoteC
  bind newPyStr, newTypeError
  for k in keys(kwargs):
      exc = newTypeError newPyStr fname & unexpKwMsgPart & quoteC & $k & quoteC
      break

template breakIfKwDictNil(kwargs; parseBlk) =
  if kwargs.isNil: break parseBlk
template withBlk(result; body){.dirty.} =
  let parseBlk = genSym(nskLabel, "blk_of_PyArg_UnpackKeywords")
  result.add getAst(breakIfKwDictNil(kwargs, parseBlk))
  body
  result.add getAst(chkUnexpectedKey(exc, kwargs, fnameNode))
  result = newBlockStmt(parseBlk, result)

template asgn(v, k){.dirty.} =
  result.add newCall(bindSym"lukImpl", exc, kwargs, v, newLit k, parseBlk)

template implWithKeywords(){.dirty.} =
  result.withBlk:
    for i, k in keywords:
      asgn(vars[i], k)

template implWithVars(){.dirty.} =
  result.withBlk:
    for i, v in vars:
      asgn(v, v.getPyNameOfParamAsStr)

template resStmt{.dirty.} =  
  result = newStmtList()
  let fnameNode = genSym(nskConst, "currentPyFuncName")
  result.add newConstStmt(
    fnameNode, newLit fname,
  )

macro PyArg_UnpackKeywords*(exc: PyBaseErrorObject; fname: static[string]; kwargs: PyDictObject; keywords: static openArray[string], vars: varargs[typed]) =
  resStmt
  implWithKeywords

macro PyArg_UnpackKeywordsTo*(exc: PyBaseErrorObject; fname: static[string]; kwargs: PyDictObject; vars: varargs[typed]) =
  resStmt
  implWithVars

#template PyArg_UnpackKeywords*(kwargs: PyDictObject; vars: varargs[typed]) =
template wrapExcAsRet(call){.dirty.} =
  let exc = genSym(nskVar, "exc_when_PyArg_UnpackKeywords")
  let pre = nnkVarSection.newTree(newIdentDefs(exc, bindSym"PyBaseErrorObject"))
  call
  result = newStmtList(
    pre,
    result,
    exc
  )

template genPyArg_VaUnpackKeywords(Vars){.dirty.} =
  # NIM-BUG: `xx|openArray` cannot accept seq pass-in (openArray cannot be in generic)
  proc PyArg_VaUnpackKeywords*(fname: string; kwargs: NimNode#[PyDictObject]#;
      keywords: openArray[string], vars: Vars#[varargs[typed]]#): NimNode#[PyBaseErrorObject]# =
    resStmt; wrapExcAsRet implWithKeywords
genPyArg_VaUnpackKeywords NimNode
genPyArg_VaUnpackKeywords openArray[NimNode]

macro PyArg_UnpackKeywords*(fname: static[string]; kwargs: PyDictObject; keywords: static openArray[string], vars: varargs[typed]): PyBaseErrorObject =
  PyArg_VaUnpackKeywords(fname, kwargs, keywords, vars)

macro PyArg_UnpackKeywordsTo*(fname: static[string]; kwargs: PyDictObject; vars: varargs[typed]): PyBaseErrorObject =
  ## like `PyArg_UnpackKeywords`_ but using `vars`'s symbol names as keywords' names
  resStmt; wrapExcAsRet implWithVars

proc predeclVars(result: var NimNode; vars: NimNode) =
  let res = newNimNode(nnkVarSection)
  let typ = bindSym"PyObject"
  for v in vars:
    res.add newIdentDefs(v, typ)
  result = newStmtList(res, result)

macro PyArg_UnpackKeywordsAs*(fname: static[string]; kwargs: PyDictObject; keywords: static openArray[string], vars: varargs[untyped]): PyBaseErrorObject =
  ## like `PyArg_UnpackKeywords`_ but it's this macro's responsibility to declare variable in `vars`
  resStmt
  wrapExcAsRet implWithKeywords
  result.predeclVars vars

macro PyArg_UnpackKeywordsToAs*(fname: static[string]; kwargs: PyDictObject; vars: varargs[untyped]): PyBaseErrorObject =
  resStmt
  wrapExcAsRet implWithVars
  result.predeclVars vars
