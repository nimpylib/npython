
from std/typeinfo import AnyKind
export AnyKind
#import ../Objects/stringobject

#[
type
  Flag = distinct int
template `|`(a, b: Flag): int = a or b.int

const
  # Flags
  Py_READONLY* =            Flag 1
  Py_AUDIT_READ* =          Flag 2 ## Added in 3.10, harmless no-op before that
  #_Py_WRITE_RESTRICTED* =  Flag 4 // Deprecated, no-op. Do not reuse the value.
  Py_RELATIVE_OFFSET* =     Flag 8

    fpmdDef     = 0
    fpmdRO      = Py_READONLY.ord
    fpmdROAudit = Py_READONLY | Py_AUDIT_READ
    fpmdRORel   = Py_READONTY | Py_RELATIVE_OFFSET
template `&`*(a: PyMemberDefFlags, b: Flag): bool = bool a.ord and b.int
]#
type
  PyMemberDefFlags* = object
    readonly*, auditRead*, relativeOffset*: bool

import std/macros
macro pyMemberDefFlagsFromTags*(tags: varargs[untyped]): PyMemberDefFlags =
  runnableExamples:
    let flags = pyMemberDefFlagsFromTags(
      readonly, auditRead
    )
    assert flags.readonly
    assert not flags.relativeOffset
  result = nnkObjConstr.newTree bindSym"PyMemberDefFlags"
  let On = newLit(true)
  for t in tags:
    result.add nnkExprColonExpr.newTree(t, On)

type
  PyMemberDef* = object
    name*: string
    `type`*: AnyKind
    offset*: int
    flags*: PyMemberDefFlags
    doc: cstring


template noRelOff*(member: PyMemberDef, funcName: string) =
  assert not member.flags.relativeOffset, "CPython's SystemError: " &
    funcName & " used with Py_RELATIVE_OFFSET"

const akPyObject* = akRef  ## `Py_T_OBJECT_EX`

proc initPyMemberDef*(name: string, `type`: AnyKind,
    offset: int; flags=default PyMemberDefFlags, doc=cstring nil): PyMemberDef =
  PyMemberDef(name: name, `type`: `type`, offset: offset, flags: flags, doc: doc)

template genTypeToAnyKind*(PyObject){.dirty.} =
  bind AnyKind
  mixin parseEnum, newLit, strVal

  template typeToAnyKind*[T: PyObject](t: typedesc[T]): AnyKind = akPyObject
  template typeToAnyKind*[Py: PyObject](t: typedesc[seq[Py]]): AnyKind = akSequence
  macro typeToAnyKind*[T](t: typedesc[T]): AnyKind =
    let res = parseEnum[AnyKind]("ak" & t.strVal)
    newLit res


  proc initPyMemberDef*[T](name: string, `type`: typedesc[T],
      offset: int; flags=default PyMemberDefFlags, doc=cstring nil): PyMemberDef =
    initPyMemberDef(name, `type`.typeToAnyKind, offset, flags, doc)


