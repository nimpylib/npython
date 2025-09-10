

import std/strformat
import ./numobjects_comm
export numobjects_comm
import ../../Python/[
  warnings,
]
template PyNumber_Xxx_Wrap*[Py: PyObject](o: PyObject; magicPureId, typeId;
    prePureFuncName: string, resTypeNameMaxLen: int; resObj: var Py){.dirty.} =
  bind warnEx, Py_CheckSlotResult, getMagic
  bind pyDeprecationWarningObjectType, retIfExc

  type T = `Py typeId Object`
  const
    magicPureName = astToStr(magicPureId)
    dunderName = "__" & magicPureName & "__"

  template ret(obj: T) =
    resObj = obj
    return nil
  template ret(obj) = ret T obj

  let fun = o.getMagic(magicPureId)
  if not fun.isNil:
    let i = fun(o)
    assert Py_CheckSlotResult(o, dunderName, i)

    template truncedObjTypename: string = i.typeName.substr(0, resTypeNameMaxLen-1)
    template returned_non_xx_but_type: string = " returned non-" & astToStr(typeId) & " (type "&truncedObjTypename&")"
    if i.`ofExactPy typeId Object`:
      ret i
    elif i.isThrownException:
      return PyBaseErrorObject i
    else:
      if not i.`ofPy typeId Object`:
        return newTypeError newPyStr(
          prePureFuncName & dunderName & returned_non_xx_but_type
        )
      # Issue #17576: warn if 'result' not of exact type int.
      # Or
      # Issue #26983: warn if 'res' not of exact type float.
      retIfExc warnEx(pyDeprecationWarningObjectType,
        prePureFuncName & dunderName & returned_non_xx_but_type & ". " &
              "The ability to return an instance of a strict subclass of int " &
              "is deprecated, and may be removed in a future version of Python."
      )
      ret i


proc PyNumber_Index*(item: PyObject, res: var PyIntObject): PyBaseErrorObject{.pyCFuncPragma.} =
  ## - returns nil if no error;
  ## - returns TypeError or other exceptions raised by `item.__index__`
  if item.isNil: return null_error()
  if item.ofPyIntObject:
    res = PyIntObject item
    return

  PyNumber_Xxx_Wrap item, index, int, "", 200, res
  return newTypeError newPyStr(
    fmt"'{item.typeName:.200s}' object cannot be interpreted as an integer"
  )
 

proc privatePyNumber_Index*(item: PyObject): PyObject{.pyCFuncPragma.} =
  ## `_PyNumber_Index`
  ##
  ## returns `PyIntObject`(or its subtype with a warning) or exception
  ## 
  ## CPython's defined at abstract.c
  var res: PyIntObject
  result = PyNumber_Index(item, res)
  if result.isNil:
    result = res

proc PyNumber_Index*(item: PyObject): PyObject{.pyCFuncPragma.} =
  ## Return an exact Python int from the object item.
  ## Raise TypeError if the result is not an int
  ## or if the object cannot be interpreted as an index.
  result = privatePyNumber_Index(item)
  retIfExc result
  if not result.ofExactPyIntObject:
    result = newPyInt PyIntObject(result)
