
template instantiationFuncname*: cstring =
  ## `__func__`
  when defined(js):
    var res{.importjs: "arguments.callee.name".}: cstring
    res
  else:
    getFrame().filename
