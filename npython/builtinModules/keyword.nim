
import ./private/utils

impObjects [
  pyobject,
  exceptions,
  bltcommon,
  stringobject,
  listobject,
  moduleobjectImpl,
  boolobject,
]
import pkg/handy_sugars/trans_imp
impExpCwd keyword, [
  funcs, pyfuncs, consts,
]

declarePyType keywordModule(base(module)):
  kwlist{.member.}: PyObject
  softkwlist{.member.}: PyObject

proc newPyListFromAsciis(asciis: openArray[string]): PyListObject =
  result = newPyList asciis.len
  for i, a in asciis:
    result[i] = newPyAscii a

const keywordModuleName* = "keyword"
proc PyInit_keyword*: PyObject =
  result = PyModule_CreateInitialized(keyword)
  retIfExc result
  let modu = PyKeywordModuleObject result
  modu.kwlist = newPyListFromAsciis kwlist
  modu.softkwlist = newPyListFromAsciis softkwlist

template gen(iskeyword) {.dirty.} =
  implkeywordModuleMethod iskeyword(x):
    if not x.ofPyStrObject: return pyFalseObj
    newPyBool iskeyword PyStrObject x

gen iskeyword
gen issoftkeyword

