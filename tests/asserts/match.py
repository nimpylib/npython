def classify(value):
    match value:
        case 0:
            return "zero"
        case 1:
            return "one"
        case _:
            return "other"


assert classify(0) == "zero"
assert classify(1) == "one"
assert classify(2) == "other"


def no_match(value):
    marker = "unchanged"
    match value:
        case 1:
            marker = "matched"
    return marker


assert no_match(0) == "unchanged"


def capture(value):
    match value:
        case item:
            return item


assert capture(7) == 7
