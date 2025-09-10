
import ./numobjects_comm
import ../abstract/helpers
export null_error

template PyNumber_FloatOrIntImpl*(o: PyObject, resObj: typed; nameId; doWithIndexRes){.dirty.} =
  type T = `Py nameId Object`
  const
    nameStr = astToStr(nameId)
    dunderName = "__" & nameStr & "__"
  template ret(obj: T) =
    resObj = obj
    return nil
  template ret(obj) = ret T obj
  if o.isNil: return null_error()
  if o.`ofExactPy nameId Object`: ret o

  let m = o.getMagic nameId
  if not m.isNil:
    let res = m(o)
    assert Py_CheckSlotResult(o, dunderName, res)
    if res.isThrownException: return PyBaseErrorObject res
    if res.`ofExactPy nameId Object`: ret res

    if not res.`ofPy nameId Object`:
      return newTypeError newPyStr fmt"{o.typeName:.50s}.{dunderName} returned non-{nameStr} (type {res.typeName:.50s})"

    # Issue #26983: warn if 'res' not of exact type float.
    retIfExc warnEx(pyDeprecationWarningObjectType,
      fmt"{o.typeName:.50s}.{dunderName} returned non-{nameStr} (type {res.typeName:.50s}).  " &
                fmt"The ability to return an instance of a strict subclass of {nameStr} " &
                "is deprecated, and may be removed in a future version of Python.")

    ret `newPy nameId` T res

  if not o.getMagic(index).isNil:
    var res: PyIntObject
    retIfExc PyNumber_Index(o, res)
    doWithIndexRes


template genNumberVariant*(Name, T){.dirty.} =
  proc `PyNumber Name`*(v: PyObject): PyObject {.pyCFuncPragma.} =
    var res: `Py T Object`
    result = `PyNumber Name`(v, res)
    if result.isNil: result = res
