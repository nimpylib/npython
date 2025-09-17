

import std/macros
import ./[kwargs, vargs, tovals, tovalUtils, paramsMeta]
export tovals, paramsMeta
import ../../Objects/[
  pyobject,
  exceptions,
  dictobject,
]

proc PyArg_VaParseTupleAndKeywords*(funcname: string, args: NimNode#[openArray[PyObject]]#, keywords: NimNode#[PyDictObject]#,
    kwOnlyList: openArray[string]; vargs: NimNode#[varargs[typed]]#): NimNode =
  let kwOnlyIdx = vargs.len-kwOnlyList.len
  result = newStmtList()
  result.add PyArg_VaParseTuple(funcname, args, 0, kwOnlyIdx, vargs)
  var kvargs = newSeqOfCap[NimNode](kwOnlyList.len)
  var kwlist: seq[string]
  for i in kwOnlyIdx..<vargs.len:
    let v = vargs[i]
    kvargs.add v
    kwlist.add v.getNameOfParam.strVal
  result.add PyArg_VaUnpackKeywords(funcname, keywords, kwList, kvargs)

proc PyArg_VaParseTupleAndKeywordsAs*(funcname: string, args: NimNode#[openArray[PyObject]]#, keywords: NimNode#[PyDictObject]#,
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
      let name = i[0]
      result.add newVarStmt(name, i[1])
      vars.add name
    elif i.kind == nnkIdentDefs:
      let varname = i[0]
      result.add nnkVarSection.newTree i
      vars.add varname
    else:
      let (varname, typ) =
        if i.kind == nnkExprColonExpr:
          (i[0], i[1])
        else:
          (i, bindSym"PyObject")
      result.add nnkVarSection.newTree newIdentDefs(varname, typ)
      vars.add varname
  result.add PyArg_VaParseTupleAndKeywords(funcname, args, keywords, kwOnlyList, vars)

macro PyArg_ParseTupleAndKeywords*(funcname: static[string], args: openArray[PyObject], keywords: PyDictObject,
    kwOnlyList: static openArray[string]; vargs: varargs[typed]): PyBaseErrorObject =
  ## vargs can be, e.g.:
  ## `v: int` or `v = 1`,
  ## also pragma like `convertVia`_ is supported
  PyArg_VaParseTupleAndKeywords(funcname, args, keywords, kwOnlyList, vargs)

macro PyArg_ParseTupleAndKeywordsAs*(funcname: static[string], args: openArray[PyObject], keywords: PyDictObject,
    kwOnlyList: static openArray[string]; vargs: varargs[untyped]): PyBaseErrorObject =
  PyArg_VaParseTupleAndKeywordsAs(funcname, args, keywords, kwOnlyList, vargs)
