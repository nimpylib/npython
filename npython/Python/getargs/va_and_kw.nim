

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

proc PyArg_VaParseTupleAndKeywords*(funcname: NimNode#[string]#, args: NimNode#[openArray[PyObject]]#, keywords: NimNode#[PyDictObject]#,
    kwOnlyList: openArray[string]; vargs: NimNode#[varargs[typed]]#): NimNode =
  let kwOnlyIdx = vargs.len-kwOnlyList.len
  result = newStmtList()
  result.add PyArg_VaParseTuple(funcname, args, 0, kwOnlyIdx, vargs)
  var kvargs = newSeqOfCap[NimNode](kwOnlyList.len)
  var kwlist: seq[string]
  for i in kwOnlyIdx..<vargs.len:
    let v = vargs[i]
    kvargs.add v
    kwlist.add v.getPyNameOfParamAsStr
  result.add PyArg_VaUnpackKeywords(funcname, keywords, kwList, kvargs)

proc PyArg_VaParseTupleAndKeywordsAs*(funcname: NimNode#[string]#, args: NimNode#[openArray[PyObject]]#, keywords: NimNode#[PyDictObject]#,
    kwOnlyList: openArray[string]; vargs: NimNode#[varargs[untyped]]#): NimNode =
  runnableExamples:
    runnableExamples:
      retIfExc PyArg_ParseTupleAndKeywordsAs(args, kwargs,
        ["start", "stop"],
        x, start=0, stop=100
      )
  result = newStmtList()

  var vars = newNimNode nnkBracket
  for i in vargs:
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
  result.add PyArg_VaParseTupleAndKeywords(funcname, args, keywords, kwOnlyList, vars)

macro PyArg_ParseTupleAndKeywords*(funcname: string, args: openArray[PyObject], keywords: PyDictObject,
    kwOnlyList: static openArray[string]; vargs: varargs[typed]): PyBaseErrorObject =
  ## vargs can be, e.g.:
  ## `v: int` or `v = 1`,
  ## also pragma like `convertVia`_ is supported
  PyArg_VaParseTupleAndKeywords(funcname, args, keywords, kwOnlyList, vargs)

macro PyArg_ParseTupleAndKeywordsAs*(funcname: string, args: openArray[PyObject], keywords: PyDictObject,
    kwOnlyList: static openArray[string]; vargs: varargs[untyped]): PyBaseErrorObject =
  PyArg_VaParseTupleAndKeywordsAs(funcname, args, keywords, kwOnlyList, vargs)
