
import ./[
  pyobject,
]
export rtarrays


type
  PyModuleDef_SlotKind* = enum
    Py_mod_unknown  ## invalid, or nim will complain object variant not start from 0
    Py_mod_create = 1
    Py_mod_exec
  PyModuleDef_Slot* = object
    case slot: PyModuleDef_SlotKind
    of Py_mod_unknown: discard  # just make sure 
    of Py_mod_create:
      create: proc (spec: PyObject, def: PyModuleDef): PyObject{.pyCFuncPragma.}
    of Py_mod_exec:
      exec: proc (m: PyObject#[PyModuleObject]#): PyObject{.pyCFuncPragma.}
  PyModuleDef_Slots* = RtArray[PyModuleDef_Slot]
  PyModuleDef* = ref object
    m_name*: string
    typ*: PyTypeObject
    m_slots*: PyModuleDef_Slots

proc newPyModuleDef*(name: string, typ: PyTypeObject): PyModuleDef =
  PyModuleDef(
    m_name: name,
    typ: typ,
  )
