
import ../../Objects/[
  pyobject, dictobject,
  exceptions,
]
import ../[
  bltinmodule_mod,
  coreconfig,
  sysmodule_instance,
]
proc pycore_init_builtins*(): PyBaseErrorObject =
  let bimod = PyBuiltin_Init(pyConfig)
  let modules = sys.modules

  retIfExc bimod

  let builtins = PyBuiltinsModuleObject bimod
  #XXX:  maybe this shall go to pyimport/targets/core.nim...
  # I cannot found where does CPython does these
  # (probably in _importlib.boostrap.py),
  #  Currently I'd like to write here
  template addModule(m) =
    modules[m.name] = m
  addModule sys
  addModule builtins

  #retIfExc PyImport_FixupBuiltin(tstate, bimod, "builtins", modules)
  #TODO:_PyImport_FixupBuiltin pyimport/builtins

  #TODO:interp.callable_cache
  #TODO:interp.common_consts

