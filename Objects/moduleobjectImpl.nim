
import std/strformat
import ./[pyobjectBase,
  moduleobject,
  exceptions,
]
export moduleobject

import ../Python/warnings
import ../Include/modsupport

proc check_api_version(name: string, module_api_version: ApiVersion): PyBaseErrorObject =
  ##[ Check API/ABI version
    Issues a warning on mismatch, which is usually not fatal.
    Returns 0 if an exception is raised.
  ]##
  if module_api_version != NPYTHON_API_VERSION and module_api_version != PYTHON_ABI_VERSION:
      retIfExc warnEx(pyRuntimeWarningObjectType,
          fmt("Python C API version mismatch for module {name:.100s}: " &
          "This Python has API version {NPYTHON_API_VERSION}, module {name:.100s} has version {module_api_version}.")
      )



template PyModule_CreateInitialized(T: typedesc[PyObject]; module: PyModuleDef, module_api_version: ApiVersion): PyObject =
  ## `_PyModule_CreateInitialized`
  bind newPyModuleImpl
  (proc (): PyObject =
    let tname = module.m_name
    retIfExc check_api_version(tname, module_api_version)
    newPyModuleImpl(T, module.typ, tname)
  )()

template PyModule_CreateInitialized*(nameId: untyped; module_api_version=NPYTHON_API_VERSION): PyObject =
  bind newPyModuleDef
  PyModule_CreateInitialized(`Py nameId ModuleObject`,
    newPyModuleDef(astToStr(nameId), `py nameId ModuleObjectType`),
    module_api_version
  )
