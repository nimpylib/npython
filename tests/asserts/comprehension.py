import xfail
l = [i for i in range(10)]
def foo():
    print(i)

xfail.xfail(foo, NameError)

for i in range(10):
    assert l[i] == i

assert [i for j in [[1, 2]] for i in j] == [1, 2]

print("ok")
