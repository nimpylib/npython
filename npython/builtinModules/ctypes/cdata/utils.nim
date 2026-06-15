
import std/macros
proc catId*(pre, n: string): NimNode = ident(pre & n)
proc prefixIdImpl*(pre: string, id: NimNode): NimNode = catId(pre, id.strVal)
proc prefixCImpl*(id: NimNode): NimNode = prefixIdImpl("c_", id)

macro prefixId*(pre: static[string], id): untyped = prefixIdImpl(pre, id)
macro prefixC*(id): untyped = prefixIdImpl("c_", id)

