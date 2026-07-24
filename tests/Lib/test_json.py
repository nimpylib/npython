import json
import math


def assert_raises(exc_type, func, *args):
    raised = False
    try:
        func(*args)
    except exc_type:
        raised = True
    assert raised


value = {
    "null": None,
    "bools": [True, False],
    "numbers": [1, -2, 3.5],
    "text": "hello",
    "nested": {"items": [1, 2]},
}

encoded = json.dumps(value)
assert json.loads(encoded) == value
assert json.loads('["escaped\\ntext", "\\u4f60\\u597d"]') == ["escaped\ntext", "你好"]
assert json.dumps((1, "two", None)) == '[1, "two", null]'
assert math.isnan(json.loads("NaN"))
assert json.loads("Infinity") == float("inf")
assert json.loads("-Infinity") == float("-inf")
assert json.loads("[NaN, Infinity, -Infinity]")[1:] == [
    float("inf"),
    float("-inf"),
]
assert_raises(json.JSONDecodeError, json.loads, "{")
assert_raises(json.JSONDecodeError, json.loads, "nan")
assert_raises(json.JSONDecodeError, json.loads, "-NaN")
assert_raises(TypeError, json.dumps, object())

assert json.loads("1") == 1
assert json.loads("12", parse_int=lambda value: value) == "12"
assert json.loads("1.25", parse_float=lambda value: value) == "1.25"

constants = []


def parse_constant(value):
    constants.append(value)
    return None


assert json.loads("[NaN, Infinity, -Infinity]", parse_constant=parse_constant) == [
    None,
    None,
    None,
]
assert constants == ["NaN", "Infinity", "-Infinity"]
assert json.loads('{"a": 1}', object_hook=lambda value: [value]) == [{"a": 1}]
assert json.loads(
    '{"a": 1}',
    object_hook=lambda value: None,
    object_pairs_hook=lambda pairs: pairs,
) == [("a", 1)]

assert json.dumps({"b": 1, "a": 2}, sort_keys=True) == '{"a": 2, "b": 1}'
assert json.dumps("你好") == '"\\u4f60\\u597d"'
assert json.dumps("😀") == '"\\ud83d\\ude00"'
assert json.dumps("你好", ensure_ascii=False) == '"你好"'
assert json.dumps([1, 2], separators=(";", "=")) == "[1;2]"
assert json.dumps({"a": [1]}, indent=2) == '{\n  "a": [\n    1\n  ]\n}'
assert json.dumps({"a": [1]}, indent="--") == '{\n--"a": [\n----1\n--]\n}'
assert json.dumps({1: "one", None: "none"}) == '{"1": "one", "null": "none"}'
assert json.dumps({object(): 1}, skipkeys=True) == "{}"
assert json.dumps(object(), default=lambda value: "fallback") == '"fallback"'
assert_raises(ValueError, lambda: json.dumps(float("nan"), allow_nan=False))

circular = []
circular.append(circular)
assert_raises(ValueError, json.dumps, circular)


class Decoder:
    def __init__(
        self,
        object_hook=None,
        parse_float=None,
        parse_int=None,
        parse_constant=None,
        object_pairs_hook=None,
        custom=None,
    ):
        self.parse_int = parse_int
        self.custom = custom

    def decode(self, source):
        return [self.parse_int(source), self.custom]


assert json.loads(
    "custom", cls=Decoder, parse_int=lambda value: value, custom=7
) == [
    "custom",
    7,
]


class Encoder:
    def __init__(
        self,
        skipkeys=False,
        ensure_ascii=True,
        check_circular=True,
        allow_nan=True,
        indent=None,
        separators=None,
        default=None,
        sort_keys=False,
        custom=None,
    ):
        self.sort_keys = sort_keys
        self.custom = custom

    def encode(self, value):
        return self.custom if self.sort_keys else "unsorted"


assert json.dumps({}, cls=Encoder, sort_keys=True, custom="sorted") == "sorted"
