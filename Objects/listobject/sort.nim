
import std/algorithm
import ../[
  pyobject,
  noneobject,
  exceptions,
  listobject,
]
import ../pyobject_apis/compare
import ../../Python/call
export listobject

using self: PyListObject
type SortCmpError = object of CatchableError
template genCmp(exc; key){.dirty.} =
  proc cmp(a, b: PyObject): int =
    var res: bool
    exc = PyObject_RichCompareBool(key a, key b, Py_LT, res)
    if not exc.isNil:
      raise new SortCmpError
    if res: -1
    else: 1
template catchAsRet(key; body): untyped =
  var exc: PyBaseErrorObject
  genCmp exc, key
  try: body
  except SortCmpError: return exc

template asIs(x): untyped = x
template sortImpl(self): untyped{.dirty.} =
  self.items.sort(cmp=cmp, order=if reversed: Descending else: Ascending)

proc sort*(self; reversed=false): PyBaseErrorObject =
  catchAsRet asIs, self.sortImpl

proc sort*(self; keyfunc: PyObject, reversed=false): PyBaseErrorObject =
  template keyTmpl(x): untyped =
    keyfunc.call(x)
  if keyfunc.isNil or keyfunc.isPyNone:
    return self.sort(reversed)
  catchAsRet keyTmpl, self.sortImpl


when isMainModule:
  import ../numobjects
  var ls = newPyList()
  ls.add newPyFloat 1.0
  ls.add newPyInt 0
  let exc = ls.sort
  if not exc.isNil:
    echo "Error:"
    echo exc
  else:
    echo ls

