
import std/dynlib
import ../../private/[utils]

impObjects [
  pyobject,
  stringobject,
  dictobject,
]

declarePyType CDLL(dict):
  path{.member"_name".}: PyStrObject
  handle{.member"_handle".}: LibHandle
