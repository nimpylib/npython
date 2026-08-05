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


def loop_else(value):
    result = 0
    for item in value:
        result = item
    else:
        result = 10
    return result


assert loop_else([1, 2]) == 10


def loop_else_break(value):
    result = 0
    for item in value:
        if item == 2:
            break
        result = item
    else:
        result += 10
    return result


assert loop_else_break([1, 2, 3]) == 1


def while_else(value):
    result = 0
    while value > 0:
        value = 0
    else:
        result = 10
    return result


assert while_else(2) == 10


def try_else(value):
    try:
        result = 10 // value
    except:
        return "error"
    else:
        return result + 1


assert try_else(2) == 6
assert try_else(0) == "error"
