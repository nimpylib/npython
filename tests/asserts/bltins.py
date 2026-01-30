"""Assert-based tests for builtin call/argument passing.

Rules: only builtin functions are tested; no user-defined functions;
do not use argument unpacking (`*` or `**`).
"""

# dict and dict.fromkeys
def test_init():
  assert dict() == {}
  #assert dict([('a', 1), ('b', 2)]) == {'a': 1, 'b': 2}
  assert dict(a=1, b=2) == {'a': 1, 'b': 2}
  assert dict.fromkeys([1, 2]) == {1: None, 2: None}
  assert dict.fromkeys([1, 2], 0) == {1: 0, 2: 0}

  # list
  assert list() == []
  assert list((1, 2, 3)) == [1, 2, 3]
test_init()

# numeric builtins: max, min
def test_min_max():
  assert max(1, 2, 3) == 3
  assert max([1, 5, 3]) == 5
  assert min([1, 0, -1]) == -1
  # use builtin `abs` as a key function
  assert max([-1, -2, 0], key=abs) == -2

  # simple sanity checks combining builtin calls
  s = set(dict.fromkeys((3, 1, 2)).keys())
  assert s == {1, 2, 3}
test_min_max()

# Grouped tests using `def` (each function is called so asserts execute)
def test_numeric_builtins():
  # # pow with two and three args
  # assert pow(2, 3) == 8
  # assert pow(2, 3, 5) == 3

  # # divmod and round
  # assert divmod(7, 3) == (2, 1)
  # assert round(2.5) in (2, 3)

  # abs and built-in conversions
  assert abs(-5) == 5
  assert int('10') + 5 == 15


def test_sequence_and_sorting():
  # conversions and sorted results
  assert list((4, 3, 2)) == [4, 3, 2]
  assert tuple([1, 2]) == (1, 2)
  assert set([1, 2, 2]) == {1, 2}
  assert sorted([3, 1, 2]) == [1, 2, 3]

  # reversed returns an iterator; collect via list()
  assert list(reversed([1, 2, 3])) == [3, 2, 1]


def test_dictionary_methods_and_lookup():
  # dict creation and lookups
  x = dict.fromkeys(['x', 'y'], 0)
  assert x == {'x': 0, 'y': 0}
  x2 = dict(a=1, b=2)
  assert x2.get('a') == 1
  x2.pop('a') == 1
  # ensure pop removed key
  assert 'a' not in x2



def test_boolean_any_all_sum():
  assert any([0, '', None, 1]) is True
  assert all([1, True, 'nonempty']) is True
  assert sum([1, 2, 3]) == 6


def test_string_and_bytes():
  assert str(123) == '123'
  b = bytes([65, 66, 67])
  assert b == b'ABC'


# Call grouped tests so their asserts run
test_numeric_builtins()
test_sequence_and_sorting()
test_dictionary_methods_and_lookup()
test_boolean_any_all_sum()
test_string_and_bytes()

