
import pkg/handy_sugars/trans_imp
when defined(js) or defined(windows):
  # Under windows: tested on 7/29/26,
  #  C compiler errors:
  #[
  error: 'FFI_SYSV' undeclared
  error: implicit declaration of function 'ffi_call_SYSV'
  
  ]#
  impExpCwd ffi, [ffi_shim]
else:
  impExpCwd ffi, [ffi_full_ugly]
