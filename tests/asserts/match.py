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


def guarded(value):
    match value:
        case item if item > 0:
            return "positive"
        case _:
            return "not positive"


assert guarded(1) == "positive"
assert guarded(0) == "not positive"


def either(value):
    match value:
        case 1 | 2:
            return "small"
        case _:
            return "other"


assert either(1) == "small"
assert either(2) == "small"
assert either(3) == "other"


def pair(value):
    match value:
        case [first, second]:
            return first + second
        case _:
            return -1


assert pair([2, 3]) == 5
assert pair([2]) == -1


def whole(value):
    match value:
        case [1, 2] as pair_value:
            return pair_value
        case _:
            return None


assert whole([1, 2]) == [1, 2]


def mapping(value):
    match value:
        case {"kind": kind}:
            return kind
        case _:
            return None


assert mapping({"kind": "ok", "extra": True}) == "ok"
assert mapping({"other": "no"}) is None


def class_case(value):
    match value:
        case int():
            return "integer"
        case _:
            return "other"


assert class_case(3) == "integer"
assert class_case("3") == "other"
