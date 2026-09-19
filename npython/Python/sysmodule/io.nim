

import ../../Objects/stringobject
import ../sysmodule_instance
import ../../Objects/abstract/call
import ../../Include/internal/pycore_global_strings

proc PySys_EchoStderr*(s: string) =
  let stderr = sys.stderr #PySys_GetObject("stderr")
  if stderr.isNil: return
  discard stderr.callMethod(pyId"write", newPyStr s)
  discard stderr.callMethod(pyId"write", newPyAscii '\n')
