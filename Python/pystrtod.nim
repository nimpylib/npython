
from std/strutils import isDigit
import ../Objects/stringobject/strformat
import ../Objects/[pyobjectBase, exceptions, stringobject,
]

proc Py_string_to_number_with_underscores*(
    s: openArray[char], what: cstring, obj: PyObject, arg: PyObject,
    innerfunc: proc (s: openArray[char], obj: PyObject): PyObject{.pyCFuncPragma.}
 ): PyObject {.pyCFuncPragma.} =
  ##[
  `_Py_string_to_number_with_underscores`

  Remove underscores that follow the underscore placement rule from
    the string and then call the `innerfunc` function on the result.
    It should return a new object or exception.

    `what` is used for the error message emitted when underscores are detected
    that don't follow the rule. `arg` is an opaque pointer passed to the inner
    function.

    This is used to implement underscore-agnostic conversion for floats
    and complex numbers.
  ]##

  template goto_error =
    let s = newPyStr&"could not convert string to {what}: {obj:R}"
    retIfExc s
    return newValueError PyStrObject s
  #assert s[orig_len] == '\0'
  let orig_len = s.len

  if '_' not_in s:
    return innerfunc(s, arg)

  var dup = (when declared(newSeqUninit): newSeqUninit else: newSeq)[char](orig_len)
  #if (dup == NULL) return PyErr_NoMemory();
  var i = 0
  var prev = '\0'

  for c in s:
    case c
    of '_':
      # Underscores are only allowed after digits.
      if not prev.isDigit:
        goto_error
    of '\0':
      # No embedded NULs allowed.
      goto_error
    else:
      dup[i] = c
      i.inc
      # Underscores are only allowed before digits.
      if prev == '_' and not c.isDigit:
        goto_error
    prev = c
  # Underscores are not allowed at the end.
  if prev == '_':
    goto_error
  return innerfunc(dup.toOpenArray(0, i), arg)
