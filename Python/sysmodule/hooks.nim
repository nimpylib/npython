
import ../../Objects/[pyobjectBase, exceptions,]
import ../pythonrun/pyerr_display


proc excepthook*(exctype: PyObject, value: PyBaseErrorObject, traceback: PyObject) =
  PyErr_Display(nil, value, traceback)
