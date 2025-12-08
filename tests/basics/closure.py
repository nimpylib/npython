def outer(x):
    def inner(y):
        return x + y
    return inner

f = outer(10)
assert f(21) == 31

g = outer(50)
assert g(31) == 81
