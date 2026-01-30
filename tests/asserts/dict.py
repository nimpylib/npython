
import xfail
def test_dictionary_methods_and_lookup():
	x2 = dict(a=1, b=2)
	assert x2.pop('a') == 1
	# ensure pop removed key
	assert 'a' not in x2

test_dictionary_methods_and_lookup()

cnt = 0
def key_error():
  ori = dict(a=1, b=2)
  x = ori.copy()
  x.pop('a')
  cnt += 1
  assert len(ori) == 2, "dict.copy wrong"

  assert 1000 == x.pop('a', 1000)
  cnt += 1

  x.pop('a')
  cnt += 1

xfail.xfail(key_error, KeyError)
assert cnt == 2


def test_dict_update():
  d = {}
  d.update(dict(a=1))
  assert d == {'a': 1}

  d.update(b=2)
  assert d == {'a': 1, 'b': 2}

  d.clear()
  d.update([('a', 2)], b=1)
  assert d == {'a': 2, 'b': 1}
test_dict_update()

