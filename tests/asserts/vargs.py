
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
