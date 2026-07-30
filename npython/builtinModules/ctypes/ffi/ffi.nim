
import pkg/handy_sugars/trans_imp
import ./ffi/consts
when NoFFI:
  impExpCwd ffi, [ffi_shim]
else:
  impExpCwd ffi, [ffi_full_ugly]
