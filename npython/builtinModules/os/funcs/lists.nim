
include ./comm
impOs listdirx
impOs path
impObjects [
  stringobject,
  listobject,
]
imp Python, sysmodule/audit
imp Python, getargs/tovals

gen_listdir seq, add

clinicGenOsSig listdir(path = ".")

