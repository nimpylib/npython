
import ../Include/internal/str

type
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

var pyConfig* = PyConfig(site_import: true)

proc Py_GetConfig*: PyConfig = pyConfig
