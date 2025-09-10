## `_warnings`


import std/strformat
import ../Utils/[compat]
import ../Objects/[warningobject, pyobject,
  stringobject, exceptions,
  tupleobjectImpl, dictobject,
  pyobjectBase]
import ../Objects/numobjects/intobject/decl
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
  #TODO:sys.stderr
  errEchoCompatNoRaise(
    # XXX: TODO: `_formatwarnmsg_impl`
    msg.formatwarnmsg_impl_nonewline
  )

proc warn_explicit(category: PyTypeObject#[typedesc[Warning]]#, message: PyStrObject,
  filename: PyStrObject, lineno: int,
  module: PyStrObject, registry: PyDictObject,
  sourceline: PyStrObject, source: PyObject,

  ): PyBaseErrorObject{.raises: [].} =
  ## `PyErr_WarnExplicitObject` of `_warnings.c`
  showwarnmsg_impl newPyWarningMessage(
    message, category, filename, lineno.newPyInt,
    #source
  )

proc warnExplicit*(category: PyTypeObject#[typedesc[Warning]]#, message: string|PyStrObject,
  filename: string, lineno: int,
  module: PyStrObject = nil, registry: PyDictObject = nil
): PyBaseErrorObject{.raises: [].} =
  ## `PyErr_WarnExplicitObject` of `_warnings.c`
  let category = (if category.isNil: pyRuntimeErrorObjectType else: category)

  #TODO:warning withWarningLock:

  warn_explicit(
    category, message.newPyStr, filename.newPyStr, lineno,
    module, registry,
    sourceline=nil, source=nil)

# TODO: another overload for `warnExplicit` with `PyWarningMessageObject`

proc do_warn(message: PyStrObject, category: PyTypeObject#[typedesc[Warning]]#,
  stack_level: int, source: PyObject, skip_file_prefixes: PyTupleObject,
): PyBaseErrorObject{.raises: [].} =
  #TODO:warning as below: fetch filename, lineno from current frame
  #[
  var
    filename, module, registry: PyObject
    lineno: int

  setup_context(stack_level, skip_file_prefixes,
    filename, lineno, module, registry)

  withWarningLock:
    result = warn_explicit(category, message, filename, lineno,
    module, registry, nil, source)
  ]#

  var
    filename = "<sys>"
    lineno = 1
  warnExplicit(category, message, filename, lineno)

proc warn_unicode(category: PyTypeObject#[typedesc[Warning]]#, message: PyStrObject,
  stacklevel: int, source: PyObject
  ): PyBaseErrorObject{.raises: [].} =
  ## Function to issue a warning message; may returns an exception.
  let category = if category.isNil: pyRuntimeWarningObjectType else: category
  do_warn(message, category, stacklevel, source, nil)

proc warnEx*(category: PyTypeObject#[typedesc[Warning]]#, message: string|PyStrObject,
  stacklevel: int = 1
  ): PyBaseErrorObject{.raises: [].} =
  ## `PyErr_WarnEx` of `_warnings.c`
  warn_unicode(category, message.newPyStr, stacklevel, nil)
