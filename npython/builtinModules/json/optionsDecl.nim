
import std/options
export options
import ../private/utils


impObjects [
  pyobject,
]

#XXX: NOTE: the fieldName of XxxOptions below must be the same as the keyword
# argument name in json.dumps/json.loads,
# otherwise PyArg_ParseTupleAndKeywordsAs will fail to parse the keywords,
#  as we use fieldNameArrayAdded in ./objFields to generate the keywords array
type DecodeOptions* = ref object
  # Callables or None
  object_hook*: PyObject
  parse_float*: PyObject
  parse_int*: PyObject
  parse_constant*: PyObject
  object_pairs_hook*: PyObject

type
  Separators* = tuple[item_separator, key_separator: string]
  OptSeparators* = Option[Separators]

type EncodeOptions* = ref object
  skipkeys*: bool
  ensure_ascii*: bool
  check_circular*: bool
  allow_nan*: bool
  sort_keys*: bool
  indent*: PyObject
  separators*: OptSeparators
  default*: PyObject
