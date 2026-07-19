trace = []


def values():
    trace.append(1)
    yield 1
    trace.append(2)
    yield 2


g = values()
assert trace == []

total = 0
for value in g:
    total = total + value

assert total == 3
assert trace == [1, 2]
assert list(values()) == [1, 2]
print("ok")
