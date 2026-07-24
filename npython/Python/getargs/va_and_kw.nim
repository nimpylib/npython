

import std/macros
import ./[kwargs, vargs, tovals, tovalUtils, paramsMeta]
export tovals, paramsMeta
import ../../Objects/[
  pyobject,
  exceptions,
  dictobject,
]

proc freshIdentLike*(n: NimNode): NimNode =
  ## unstable. internal.
  ident:
    if n.kind == nnkAccQuoted:
      var res: string 
      for i in n: res.add i.strVal
      res
    else: n.strVal

proc freshParamName(n: NimNode): NimNode =
  if n.kind == nnkPragmaExpr:
    result = n.copyNimTree
    result[0] = freshIdentLike(n[0])
  else:
    result = freshIdentLike(n)

proc freshIdentDef(i: NimNode): NimNode =
  result = i.copyNimTree
  result[0] = freshParamName(i[0])

proc splitRestKwargs(vargs: NimNode): tuple[
    params: seq[NimNode], restKwargs: NimNode] =
  for arg in vargs:
    result.params.add arg
  if result.params.len == 0:
    return
  let last = result.params[^1]
  if last.kind == nnkPrefix and last[0].eqIdent"**":
    last.expectLen 2
    result.restKwargs = last[1]
    result.params.setLen(result.params.len - 1)
  for param in result.params:
    if param.kind == nnkPrefix and param[0].eqIdent"**":
      error "**kwargs must be the final parameter", param

proc PyArg_VaParseTupleAndKeywords*(funcname: NimNode#[string]#, args: NimNode#[openArray[PyObject]]#, keywords: NimNode#[PyDictObject]#,
    kwOnlyList: openArray[string]; vargs: NimNode#[varargs[typed]]#): NimNode =
  let (params, restKwargs) = splitRestKwargs(vargs)
  let kwOnlyIdx = params.len-kwOnlyList.len
  if kwOnlyIdx < 0:
    error "more keyword-only names than parameters"
  let paramNodes = newNimNode nnkBracket
  for param in params:
    paramNodes.add param
  result = newStmtList()
  result.add PyArg_VaParseTuple(funcname, args, 0, kwOnlyIdx, paramNodes)
  var kvargs = newSeqOfCap[NimNode](kwOnlyList.len)
  var kwlist: seq[string]
  for i in kwOnlyIdx..<params.len:
    let v = params[i]
    kvargs.add v
    kwlist.add v.getPyNameOfParamAsStr
  if restKwargs.isNil:
    result.add PyArg_VaUnpackKeywords(funcname, keywords, kwList, kvargs)
  else:
    result.add PyArg_VaUnpackKeywordsWithRest(
      funcname, keywords, kwList, kvargs, restKwargs)

proc PyArg_VaParseTupleAndKeywordsAs*(funcname: NimNode#[string]#, args: NimNode#[openArray[PyObject]]#, keywords: NimNode#[PyDictObject]#,
    kwOnlyList: openArray[string]; vargs: NimNode#[varargs[untyped]]#): NimNode =
  runnableExamples:
    runnableExamples:
      retIfExc PyArg_ParseTupleAndKeywordsAs("func", args, kwargs,
        ["start", "stop"],
        x, start=0, stop=100, **rest
      )
  result = newStmtList()

  var vars = newNimNode nnkBracket
  let (params, restKwargs) = splitRestKwargs(vargs)
  for i in params:
    if i.kind == nnkExprEqExpr:
      let name = freshParamName(i[0])
      result.add newVarStmt(name, i[1])
      vars.add name
    elif i.kind == nnkIdentDefs:
      let paramDef = freshIdentDef(i)
      let varname = paramDef[0]
      result.add nnkVarSection.newTree paramDef
      vars.add varname
    else:
      let (varname, typ) =
        if i.kind == nnkExprColonExpr:
          (freshParamName(i[0]), i[1])
        else:
          (freshParamName(i), bindSym"PyObject")
      result.add nnkVarSection.newTree newIdentDefs(varname, typ)
      vars.add varname
  if not restKwargs.isNil:
    let restName = freshIdentLike(restKwargs)
    result.add newVarStmt(restName, newCall(bindSym"newPyDict"))
    vars.add nnkPrefix.newTree(ident"**", restName)
  result.add PyArg_VaParseTupleAndKeywords(
    funcname, args, keywords, kwOnlyList, vars)

macro PyArg_ParseTupleAndKeywords*(funcname: string, args: openArray[PyObject], keywords: PyDictObject,
    kwOnlyList: static openArray[string]; vargs: varargs[untyped]): PyBaseErrorObject =
  ## vargs can be, e.g.:
  ## `v: int` or `v = 1`,
  ## also pragma like `convertVia`_ and a trailing `**kwargs` are supported
  PyArg_VaParseTupleAndKeywords(funcname, args, keywords, kwOnlyList, vargs)

macro PyArg_ParseTupleAndKeywordsAs*(funcname: string, args: openArray[PyObject], keywords: PyDictObject,
    kwOnlyList: static openArray[string]; vargs: varargs[untyped]): PyBaseErrorObject =
  PyArg_VaParseTupleAndKeywordsAs(funcname, args, keywords, kwOnlyList, vargs)
