
include ./comm
impOs subp
impOs utils
impObjects [
  stringobject,
  byteobjects,
  numobjects/intobject,
]

imp Python, sysmodule/audit
imp Python, getargs/tovals

clinicGenOsSig system(command: string), [], auditArgs=(command,)  # as `system` is also Nim's builtin module name
clinicGenOs chdir, auditArgs=(path,)
clinicGenOs getcwd
clinicGenOs getcwdb
