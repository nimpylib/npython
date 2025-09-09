

import ../../Objects/[
  pyobject,
  moduleobject,
  dictobject,
]
declarePyType SysModule(base(Module)):
  modules{.member.}: PyDictObject  # dict[str, Module]

