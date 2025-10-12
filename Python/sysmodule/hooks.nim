
import ../../Objects/[
  pyobjectBase, exceptions,
  noneobject,
  stringobject,
  ]
import ../../Objects/pyobject_apis/[attrs, io]
import ../pythonrun/pyerr_display
import ../pyimport/utils
import ../../Include/internal/pycore_global_strings
import ../../Utils/[fileio,]

proc excepthook*(exctype: PyObject, value: PyBaseErrorObject, traceback: PyObject) =
  PyErr_Display(nil, value, traceback)

proc displayhook_impl*(o: PyObject): PyBaseErrorObject =
  var builtins: PyObject
  retIfExc PyImport_GetModule(pyId(builtins), builtins)
  if builtins.isNil:
    return newRuntimeError newPyAscii"lost builtins module"
  retIfExc builtins

  # Print value except if None
  # After printing, also assign to '_'
  # Before, set '_' to None to avoid recursion
  if o.isPyNone: return
  retIfExc PyObject_SetAttr(builtins, newPyAscii('_'), pyNone)

  #TODO:sys.stdout
  #TODO:encoding
  #[
  var outf: PyObject
  retIfExc PySys_GetAttr(pyId(stdout), outf)
  if outf.isPyNone:
    return newRuntimeError newPyAscii"lost sys.stdout"
  let res = PyFile_WriteObject(o, outf)
  if res.ofPyUnicodeEncodeErrorObject:
    #[/* repr(o) is not encodable to sys.stdout.encoding with
      * sys.stdout.errors error handler (which is probably 'strict') */]#
    retIfExc sys_displayhook_unencodable(outf, o)
  retIfExc res
  retIfExc PyFile_WriteObject(newPyAscii('\n'), outf, Py_PRINT_RAW)
  ]#


  let res = PyObject_Println(o, fileio.stdout)  
  retIfExc res

  retIfExc PyObject_SetAttr(builtins, newPyAscii('_'), o)

proc displayhook*(o: PyObject): PyObject =
  retIfExc displayhook_impl(o)
  return pyNone
