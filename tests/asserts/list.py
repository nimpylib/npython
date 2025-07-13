l = [1,3.01,2,3,4,5, 1]


assert len(l) == 7


l.append(False)


assert not l[-1]


assert l.count(1) == 2


assert l.index(3) == 3


l.insert(0, 0)


assert l[0] == 0


l.pop()


assert l.pop() == 1

l[-1] = 100


assert l.pop() == 100

ls2 = [1, 2, 2]
ls2.remove(2)
assert ls2[-1] == 2

print("ok")
