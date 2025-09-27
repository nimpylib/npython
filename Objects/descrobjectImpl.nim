
import std/strformat
import ./[
  pyobject,
  noneobject,
  exceptions,
  stringobject,
  methodobject,
]
import ./descrobject
import ../Python/[
  structmember,
]
import ../Python/call
import ../Python/sysmodule/audit
{.used.}
methodMacroTmpl(Property)
implPropertyMagic get:
  fastCall(self.getter, [other])


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


methodMacroTmpl(MethodDescr)

implMethodDescrMagic call:
  #call(bound, args, kwargs)
  let argc = len(args);
  if argc < 1:
    return newTypeError newPyStr(
      fmt"descriptor '{$?self}' of '{self.truncedTypeName}' " &
      "object needs an argument"
                )
  let owner = args[0]
  let bound = tpMagic(MethodDescr, get)(self, owner)
  #let bound = method_get(self, owner)
  retIfExc bound
  tpMagic(NimFunc, call)(bound, args.toOpenArray(1, args.high), kwargs)

methodMacroTmpl(ClassMethodDescr)
implClassMethodDescrMagic call:
  ##[Instances of classmethod_descriptor are unlikely to be called directly.
   For one, the analogous class "classmethod" (for Python classes) is not
   callable. Second, users are not likely to access a classmethod_descriptor
   directly, since it means pulling it from the class __dict__.

   This is just an excuse to say that this doesn't need to be optimized:
   we implement this simply by calling __get__ and then calling the result.]##
  let argc = len(args);
  if argc < 1:
    return newTypeError newPyStr(
      fmt"descriptor '{$?self}' of '{self.truncedTypeName}' " &
      "object needs an argument"
                )
  #let owner = args[0]
  let bound = classmethod_get(self, nil, self.dType)
  retIfExc bound
  tpMagic(NimFunc, call)(bound, args#.toOpenArray(1, args.high)
    , kwargs)


