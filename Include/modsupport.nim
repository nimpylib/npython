
type ApiVersion* = distinct int
proc `==`*(a, b: ApiVersion): bool{.borrow.}
proc `$`*(a: ApiVersion): string{.borrow.}

converter toInt*(a: ApiVersion): int = int(a)

const
  NPYTHON_API_VERSION* = ApiVersion 0
  ##[
  .. hint:: this is not `PYTHON_API_VERSION` as NPython API currently isn't compatible with CPython

  The API version is maintained (independently from the Python version)
   so we can detect mismatches between the interpreter and dynamically
   loaded modules.  These are diagnosed by an error message but
   the module is still loaded (because the mismatch can only be tested
   after loading the module).  The error message is intended to
   explain the core dump a few seconds later.

   The symbol PYTHON_API_STRING defines the same value as a string
   literal.  *** PLEASE MAKE SURE THE DEFINITIONS MATCH. ***

   Please add a line or two to the top of this log for each API
   version change:

]##
  NPYTHON_API_STRING* = $NPYTHON_API_VERSION

  PYTHON_ABI_VERSION* = ApiVersion 3
  PYTHON_ABI_STRING* = $PYTHON_ABI_VERSION
