import ../private/[utils]
import ./[dll]

impObjects [
  pyobject,
  moduleobject,
]

declarePyType CTypesModule(base(Module)):
  cdll: PyCDLLObject

