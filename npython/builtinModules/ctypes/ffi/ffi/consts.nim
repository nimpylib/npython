const NoFFI* = defined(js) or defined(windows) or defined(macosx)
  # Under windows: tested on 7/29/26,
  #  C compiler errors:
  #[
  error: 'FFI_SYSV' undeclared
  error: implicit declaration of function 'ffi_call_SYSV'
  
  ]#
  # under macos: tested on 8/1/26
  # Runtime errors:
  #[
  could not import: ffi_type_longdouble
  ]#
