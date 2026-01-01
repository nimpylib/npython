
a = (1+2)
assert a == 3, a
t = (3,)
assert type(t) == tuple
assert type((1, 2, 3)) == tuple

i = 'sth'
LS = [[1, 2]]
ls = [
  i for j in LS for i in j
]
assert ls == [1, 2]
assert i == 'sth'

assert [ i for i in [1, -1, 2] if 0 < i ] == [1, 2]


D = {
  i: j for i in [1, -1, 2] for j in ['c'] if 0 < i
}

assert { i for i in [1, -1, 2] if 0 < i } == {1, 2}
assert D == {1: 'c', 2: 'c'}
