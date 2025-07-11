


type
  PyConfig = object
    filepath*: string
    filename*: string
    quiet*, verbose*: bool
    path*: string  # sys.path, only one for now

var pyConfig* = PyConfig()

