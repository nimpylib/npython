## polyfill as Windows cannot import pkg/libffi
import ./consts

when NoFFI:
  type
    Closure* = object
    TCif* = object
    Type* = object


  proc closure_free*(x: ptr Closure) = discard
else:
  import pkg/libffi as araqlibffi
  export araqlibffi
