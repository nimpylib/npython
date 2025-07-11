


type
  PyConfig = object
    filepath*: string
    filename*: string
    path*: string  # sys.path, only one for now

var pyConfig* = PyConfig()

