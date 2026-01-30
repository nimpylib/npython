
assert id(locals()) == id(globals())

def f():
    a = 123
    assert id(locals()) != id(globals())
    assert locals()['a'] == 123
    assert 'a' in locals()
    assert 'a' not in globals()

f()

