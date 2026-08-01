import ../private/[utils]
import ./dll/decl

impObjects [
  pyobject,
  moduleobject,
]

declarePyType CTypesModule(base(Module)):
  cdll: PyCDLLObject

