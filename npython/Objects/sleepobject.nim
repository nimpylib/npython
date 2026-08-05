import pyobject

declarePyType SleepAwaitable():
  milliseconds: int

proc newPySleepAwaitable*(milliseconds: int): PySleepAwaitableObject =
  result = newPySleepAwaitableSimple()
  result.milliseconds = milliseconds
