
import ../private/utils
impObjects [
  pyobject,
  moduleobjectImpl,
  stringobject,
]

declarePyType OsModule(base(Module)):
  dotname{.member"name", readonly.}: PyStrObject  # name exists in module (md_name in CPython)
