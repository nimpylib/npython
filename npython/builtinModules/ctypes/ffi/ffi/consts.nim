const NoFFI* = defined(js) or defined(windows)
  # Under windows: tested on 7/29/26,
  #  C compiler errors:
  #[
  error: 'FFI_SYSV' undeclared
  error: implicit declaration of function 'ffi_call_SYSV'
  
  ]#

