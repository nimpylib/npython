
def f(x, *a):
    return a + (x,)

assert f(1, 2, 3) == (2, 3, 1)

def ff(n, *a, x=7):
    assert len(a) == n
    return a + (x,)

assert ff(2, 8, 9) == (8, 9, 7)

def unpack_call(a, b, c=0, *rest, x=0):
    return (a, b, c, rest, x)

args = (2, 3)
kw = {'c': 4}

assert unpack_call(1, *args) == (1, 2, 3, (), 0)
assert unpack_call(1, **kw, b=2) == (1, 2, 4, (), 0)
assert unpack_call(1, *args, **{'x': 5}) == (1, 2, 3, (), 5)

class O:
    
    def f(self, ls=[]):
        ls.append(1)
        return ls
    
    def m(self, n, *ls):
        assert type(self) == O
        assert len(ls) == n


o = O()
assert o.f() == [1]
assert o.f() == [1, 1]

o.m(2, 1, 2)


def collect(**kw):
    return kw


assert collect() == {}
assert collect(a=1, b=2) == {'a': 1, 'b': 2}
assert collect(**{'x': 3}) == {'x': 3}


def mixed(a=1, *args, flag=2, **kw):
    return a, args, flag, kw


assert mixed() == (1, (), 2, {})
assert mixed(3, 4, flag=5, extra=6) == (3, (4,), 5, {'extra': 6})
assert mixed(a=7, other=8) == (7, (), 2, {'other': 8})


class K:
    def method(self, value, **kw):
        return value, kw


assert K().method(1, answer=42) == (1, {'answer': 42})
assert (lambda **kw: kw)(value=9) == {'value': 9}


def capture(**kw):
    def inner():
        return kw
    return inner()


assert capture(captured=True) == {'captured': True}
