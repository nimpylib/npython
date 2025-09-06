import pyobject
import ./exceptions
import frameobject
import funcobject

import ../Python/neval

export funcobject

methodMacroTmpl(Function)
methodMacroTmpl(BoundMethod)


implFunctionMagic call:
  # todo: eliminate the nil
  let f = newPyFrame(self, args, nil)
  if f.isThrownException:
    return f
  PyFrameObject(f).evalFrame


implBoundMethodMagic call:
  # todo: eliminate the nil
  let f = newPyFrame(self.fun, @[self.self] & args, nil)
  if f.isThrownException:
    return f
  PyFrameObject(f).evalFrame
