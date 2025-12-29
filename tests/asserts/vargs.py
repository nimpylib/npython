
def f(x, *a):
    return a + (x,)

assert f(1, 2, 3) == (2, 3, 1)

def ff(n, *a, x=7):
    assert len(a) == n
    return a + (x,)

assert ff(2, 8, 9) == (8, 9, 7)

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

