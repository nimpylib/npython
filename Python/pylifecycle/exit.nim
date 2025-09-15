
proc Py_Exit*(sts: int) {.noReturn.}=
  var sts = sts
  #TODO:Py_Finalize
  quit sts
