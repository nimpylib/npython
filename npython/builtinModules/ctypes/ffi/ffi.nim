
import pkg/handy_sugars/trans_imp
when defined(js):
  impExpCwd ffi, [ffi_shim]
else:
  impExpCwd ffi, [ffi_full_ugly]
