
import ../numobjects_comm
import pkg/intobject/ops_basic_arith
import ./private/dispatch

using self: PyIntObject

proc `<`*(a, b: PyIntObject): bool = a.v < b.v
proc `==`*(a, b: PyIntObject): bool = a.v == b.v

dispatchBin `+`
dispatchBin `-`
dispatchBin `*`

dispatchUnary `-`
dispatchUnary abs
