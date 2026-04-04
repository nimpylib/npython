
import ../[
  pyobject,
  noneobject,
  exceptions,
  listobject,
]
import ./sort
import ../../Python/getargs/[dispatch, paramsMeta,]


proc list_sort_impl(self: PyObject; keyfunc{.startKwOnly.}: PyObject = pyNone, reversed = false): PyObject{. clinicGenMeth(builtin_sort, true) .}= 
  let self = PyListObject self
  retIfExc self.sort(keyfunc, reversed)
  pyNone
