def f(n, x=[]):
    x.append(n)
    return x
assert f(7) == [7]
assert f(1, [3]) == [3, 1]
assert f(2) == [7, 2]
