
import pkg/pymath
include ./comm
import ./utils
impObj [
  iterobject,
  stringobject,
]

type FltItor = ref object
  o: PyObject
  exc: PyBaseErrorObject
proc floatsItor(q: PyObject): FltItor =
  new result
  result.o = q

iterator items(x: FltItor): float =
  block Full:
    var f: float
    template breakOnExc(e) =
      if e.isNil.not and e.isThrownException:
        x.exc = e
        break Full
    pyForInWithExc obj, x.o, breakOnExc:
      let exc = PyFloat_AsDouble(obj, f)
      breakOnExc exc
      yield f

proc fsum*(q: PyObject): PyObject{.pyCFuncPragma.} =
  let it = floatsItor q
  let res = fsum(it).orRetValOrOvfErr
  retIfExc it.exc
  result = newPyFloat res

implMathModuleMethod fsum(q): fsum(q)

when isMainModule:
  impObj listobject
  let ls = newPyList [
    PyObject newPyFloat 1.2,
    newPyFloat 1.2,
  ]
  echo fsum ls

