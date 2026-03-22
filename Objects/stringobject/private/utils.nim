
from pkg/pystrutils/err import TypeError; export TypeError

proc cap_stop*[P](self: P, stop: int): int =
  if stop > self.len: self.len
  else: stop

template retTypeError*(body): untyped =
  try: result = body
  except TypeError as e:
    result = newTypeError(newPyStr e.msg)

template retValueErrorAscii*(body): untyped =
  try: result = body
  except ValueError as e:
    result = newValueError(newPyAscii e.msg)


iterator items*[S: string|seq](s: tuple[before, sep, after: S]): S =
  yield s.before
  yield s.sep
  yield s.after

