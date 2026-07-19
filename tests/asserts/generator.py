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


def receiver():
    received = yield 1
    yield received


receiver_gen = receiver()
assert receiver_gen.send(None) == 1
assert receiver_gen.send(42) == 42


state = receiver()
assert state.gi_running == False
assert state.gi_suspended == False
assert state.gi_yieldfrom is None
assert state.gi_code is not None
assert state.gi_frame is not None
assert state.send(None) == 1
assert state.gi_suspended == True


def running_state():
    yield running_gen.gi_running


running_gen = running_state()
assert running_gen.send(None) == True
assert state.close() is None
assert state.gi_frame is None
assert state.gi_suspended == False

thrower = values()
threw = False
try:
    thrower.throw(ValueError)
except ValueError:
    threw = True

assert threw
assert thrower.gi_frame is None


def delegated():
    yield from [3, 4]


delegate = delegated()
assert delegate.send(None) == 3
assert delegate.gi_yieldfrom is not None
assert delegate.send(None) == 4
assert list(delegated()) == [3, 4]


def delegation_result():
    result = yield from [5]
    yield result

assert list(delegation_result()) == [5, None]
assert list(x * 2 for x in [1, 2, 3]) == [2, 4, 6]
print("ok")
