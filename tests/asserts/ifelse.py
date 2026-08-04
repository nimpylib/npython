a = 1


if a:
    assert 5
else:
    assert False


print("ok")


def classify(value):
    if value < 0:
        return "negative"
    elif value == 0:
        return "zero"
    elif value < 10:
        return "small"
    else:
        return "large"


assert classify(-1) == "negative"
assert classify(0) == "zero"
assert classify(3) == "small"
assert classify(10) == "large"
