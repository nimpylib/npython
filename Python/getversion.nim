
import ./versionInfo
export versionInfo

proc Py_GetVersion*: string =
  Version  # TODO with buildinfo, compilerinfo in form of "%.80s (%.80s) %.80s"

