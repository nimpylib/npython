

import ../../Objects/[
  pyobject,
  moduleobject,
  dictobject,
  listobject,
]
export name, `name=`
declarePyType SysModule(base(Module)):
  modules{.member.}: PyDictObject  # dict[str, Module]
  path{.member.}: PyListObject  # list[str]
  argv{.member.}: PyListObject  # list[str]
  orig_argv{.member.}: PyListObject  # list[str]

