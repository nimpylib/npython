import ./defines_gil
const
  Py_BUILD_CORE* = appType != "lib"
  Py_BUILD_CORE_MODULE* = Py_BUILD_CORE  #TODO:defined right?

  Py_DEBUG* = defined(debug)

  Py_GIL_DISABLED* = not SingleThread  ## CPython's no gil means lock is needed

  MS_WINDOWS* = defined(windows)
