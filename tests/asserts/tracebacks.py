
def g0():
  raise ValueError

def g():
  g0()
def f():
  g()

try:
  f()
except ValueError as e:
  tb = e.__traceback__
  ls = []
  while tb is not None:
    code = tb.tb_frame.f_code
    assert code.co_filename == __file__
    ls.append(code.co_name)
    tb = tb.tb_next
  assert ls == ['<module>', 'f', 'g', 'g0'], ls
