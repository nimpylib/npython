
import ../Include/internal/str

type

  PyImportTimePerf*{.pure.} = enum
    Unknown = -1
    Off = 0
    PrintOnlyUnLoaded = 1
    PrintAlsoLoaded = 2 ## print an import time entry even if an imported module has already been loaded.
  PyConfig* = object
    run_command*,
      run_module*,
      run_filename*: string
    filename*: string
    quiet*, verbose*: bool
    executable*: string
    program_name*: string
    module_search_paths*,
      argv*, orig_argv*
        :seq[Str]
    optimization_level*: int
    interactive*: bool
    site_import*: bool  ## if `import site` (no `-S` given)
    inspect*: bool
    import_time*: PyImportTimePerf = Unknown

var pyConfig* = PyConfig(site_import: true)

proc Py_GetConfig*: PyConfig = pyConfig
