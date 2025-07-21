## `_warnings`

import std/strformat
import ../Utils/compat
import ../Objects/[warningobject, stringobject, numobjects, pyobjectBase]
export warningobject

proc formatwarnmsg_impl_nonewline(msg: PyWarningMessageObject): string{.raises: [].} =
  ## `_formatwarnmsg_impl` of `Lib/_py_warnings.py`
  ## but without the tailing newline
  let category = msg.categoryName
  let
    filename = msg.filename.str
    linenoObj = msg.lineno
    message = msg.message.str
  let linenoS =
    try: $linenoObj
    except Exception: "<unknown lineno>"  ## Handle potential exceptions
  result = fmt"{filename}:{linenoS}: {category}: {message}"  ## Use the new message variable

  # TODO: linecache.getline(msg.filename, msg.lineno)
  # TODO: tracemalloc.get_object_traceback(msg.source)


proc showwarnmsg_impl(msg: PyWarningMessageObject){.raises: [].} =
  ## `_showwarnmsg_impl` of `Lib/_py_warnings.py`
  # _formatwarnmsg
  ## TODO: sys.stderr
  try:
    errEchoCompat(
      # XXX: TODO: `_formatwarnmsg_impl`
      msg.formatwarnmsg_impl_nonewline
    )
  except IOError: discard
  except Exception: discard  ## workaround for NIM-BUG about `$`'s callMagic has `Exception` exception

proc warnExplicit*(category: PyTypeObject#[typedesc[Warning]]#, message: string, filename: string, lineno: int,
    #module: string, registry: PyObject
  ){.raises: [].} =
  ## `warn_explicit` of `_warnings.c`
  showwarnmsg_impl newPyWarningMessage(
    message.newPyStr, category, filename.newPyStr, lineno.newPyInt,
    #source
  )

# TODO: another overload for `warnExplicit` with `PyWarningMessageObject`

