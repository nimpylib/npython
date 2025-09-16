

import ../getversion
import ../../Utils/[getplatform, ]
proc getVersionString*(verbose=false): string =
  result = "NPython "
  if not verbose:
    result.add Version
    return
  result.add Py_GetVersion()
  result.add " on "
  result.add PLATFORM
