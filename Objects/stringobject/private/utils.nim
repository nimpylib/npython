
template retValueErrorAscii*(body): untyped =
  try: result = body
  except ValueError as e:
    result = newValueError(newPyAscii e.msg)


iterator items*[S: string|seq](s: tuple[before, sep, after: S]): S =
  yield s.before
  yield s.sep
  yield s.after

