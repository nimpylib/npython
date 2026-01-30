
def f():
  raise ValueError

g = None
try: f()
except ValueError as e: g = e

tb = g.__traceback__
nb = tb.tb_next.tb_frame.f_back
assert nb is tb.tb_frame, nb


