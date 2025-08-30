
import ./pyobject
import ./noneobject
import ./descrobject
import ./exceptions
import ../Python/[
  structmember,
  sysmodule,
]
{.used.}
methodMacroTmpl(MemberDescr)

implMemberDescrMagic get:
  if other.isNil:
    return self
  descr_check(self, other)
  if unlikely self.d_member.flags.auditRead:
    retIfExc audit("object.__getattr__",
      #[ XXX: PY-BUG: `obj ? obj : Py_None` is unnecessary,
      as other (called `obj` in CPython) cannot be nil here.
      ]#
      other, self.d_member.name
    )
  result = PyMember_GetOne(other, self.d_member)
  retIfExc result


implMemberDescrMagic set:
  let obj = arg1
  descr_check(self, obj)
  retIfExc PyMember_SetOne(obj, self.d_member, arg2)
  pyNone

