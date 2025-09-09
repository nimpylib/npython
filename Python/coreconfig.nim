
import ../Include/internal/str

type
  PyConfig* = object
    filepath*: string
    filename*: string
    quiet*, verbose*: bool
    executable*: string
    module_search_paths*,
      argv*, orig_argv*
        :seq[Str]

var pyConfig* = PyConfig()

