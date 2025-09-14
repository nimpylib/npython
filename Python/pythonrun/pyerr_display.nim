

import ../../Objects/[
  pyobject,
  exceptions,
]
import ../[
  traceback,
]
import ../../Utils/compat


proc PyErr_Display*(unused: PyObject#[PyTypeObject]#, value: PyBaseErrorObject; tb: PyObject) {.raises: [].} =
  #TODO:PyErr_Display  after PyObject_Dump, _PyErr_Display
  try:
    value.printTb
  except IOError: discard
  except KeyError as e:
    try: errEchoCompat("Nim: KeyError when PyErr_Display: " & e.msg)
    except IOError: discard

proc PyErr_DisplayException*(exc: PyBaseErrorObject) = PyErr_Display(nil, exc, nil)
