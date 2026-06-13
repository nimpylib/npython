
import ../../Objects/[
  pyobject,
  moduleobjectImpl,
]

const mathModuleName* = "math"
declarePyType MathModule(base(Module)): discard
proc PyInit_math*: PyObject = PyModule_CreateInitialized(math)

