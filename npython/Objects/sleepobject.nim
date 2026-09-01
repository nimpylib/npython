import pyobject

declarePyType SleepAwaitable():
  milliseconds: Natural

proc newPySleepAwaitable*(milliseconds: Natural): PySleepAwaitableObject =
  result = newPySleepAwaitableSimple()
  result.milliseconds = milliseconds
