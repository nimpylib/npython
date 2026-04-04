
import ./numobjects_comm_with_warn

template PyNumber_FloatOrIntImpl*(o: PyObject, resObj: typed; nameId; doWithIndexRes){.dirty.} =
  bind PyNumber_Xxx_Wrap, PyNumber_Index
  if o.isNil: return null_error()
  if o.`ofExactPy nameId Object`:
    resObj = `Py nameId Object` o
    return
  PyNumber_Xxx_Wrap o, nameId, nameId, fmt"{o.typeName:.50s}.", 50, resObj
  if not o.getMagic(index).isNil:
    var res: PyIntObject
    retIfExc PyNumber_Index(o, res)
    doWithIndexRes

template genNumberVariant*(Name, T){.dirty.} =
  proc `PyNumber Name`*(v: PyObject): PyObject {.pyCFuncPragma.} =
    var res: `Py T Object`
    result = `PyNumber Name`(v, res)
    if result.isNil: result = res
