
import std/macros
import ./modsupport
import ./call
import ../Objects/[
  pyobject,
  stringobject,
  dictobject,
  tupleobject,
  exceptions,
]

var
  modules* = newPyDict()  # dict[str, Module]

type Py_AuditHookFunction* =
  proc(event: cstring, eventArg: PyTupleObject, userData: pointer
  ): PyBaseErrorObject ## XXX: CPython's returns `cint`,
  ## but we use `PyBaseErrorObject` to avoid global Exception.

var
  audit_hooks: seq[PyObject]  ## PyInterpreterState.audit_hooks
  rt_audit_hooks: seq[
    tuple[
      hookCFunction: Py_AuditHookFunction,
      userData: pointer
    ]
  ]  ## PyRuntimeState.audit_hooks

proc auditTupleImpl(event: cstring, eventStr: PyStrObject, args: PyTupleObject): PyBaseErrorObject =
  for i in rt_audit_hooks:
    retIfExc i.hookCFunction(event, args, i.userData)
  for i in audit_hooks:
    retIfExc fastCall(i, [eventStr, args])
proc auditTuple*(event: cstring, args: PyTupleObject): PyBaseErrorObject =
  auditTupleImpl event, newPyAscii(event), args

macro auditImpl(event: cstring, args: typed): PyBaseErrorObject =
  let tup = Py_VaBuildTuple(args)
  newCall(bindSym("auditTuple"), event, tup)

template audit*(event: cstring, args: varargs[typed]): PyBaseErrorObject = auditImpl(event, args)

#proc sys_audit*(event: PyStrObject, *args): PyObject = auditImpl(event, args)

proc addaudithook*(hook: Py_AuditHookFunction, userData: pointer = nil): PyBaseErrorObject =
  ## `PySys_AddAuditHook`
  retIfExc audit"sys.addaudithook"
  rt_audit_hooks.add (hook, userData)


proc addaudithook*(hook: PyObject): PyBaseErrorObject =
  retIfExc audit"sys.addaudithook"
  audit_hooks.add hook
