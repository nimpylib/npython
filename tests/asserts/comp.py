
i = 'sth'
LS = [[1, 2]]
ls = [
  i for j in LS for i in j
]
assert ls == [1, 2]
assert i == 'sth'

assert [ i for i in [1, -1, 2] if 0 < i ] == [1, 2]
