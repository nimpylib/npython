## workaround, currently assume only one `sys.modules` exists


import ./sysmodule/decl
export decl

var sys*: PySysModuleObject  ## unstable
# will be init via PySys_Create in pyInit

